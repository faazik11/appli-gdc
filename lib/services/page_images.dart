import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'file_store.dart';

/// Pages d'un PDF converties en images (une seule fois, puis gardées sur l'appareil).
/// Les pages s'affichent ensuite instantanément, même hors connexion.
class PageImages extends ChangeNotifier {
  final String bucket;
  final String path;
  final int width;

  PageImages({required this.bucket, required this.path, required this.width});

  /// Largeur de rendu en pixels pour un écran, arrondie pour réutiliser les pages déjà préparées.
  static int widthFor(double logicalWidth, double logicalHeight, double pixelRatio) {
    final px = max(logicalWidth, logicalHeight) * pixelRatio;
    return ((px / 200).ceil() * 200).clamp(800, 1600);
  }

  List<Uint8List?> pages = const [];

  /// Hauteur / largeur des pages (d'après la première) et sommaire du PDF.
  double ratio = 1.414;
  List<OutlineEntry> outline = const [];

  /// PDF brut, utilisé quand le rendu en images n'est pas disponible (applis mobiles pour l'instant).
  Uint8List? pdf;
  bool get fallback => pdf != null && pages.isEmpty && error == null && _done;
  String? error;
  int _focus = 0;
  bool _done = false;
  bool _disposed = false;
  PageRenderer? _renderer;

  int get ready => pages.where((p) => p != null).length;
  bool get loading => !_done || (pages.isNotEmpty && ready < pages.length);

  /// Page à préparer en priorité (celle affichée).
  set focus(int page) => _focus = page;

  Future<void> start() async {
    try {
      final bytes = await FileStore.instance.load(bucket, path);
      if (_disposed) return;
      final renderer = await openPageRenderer(bytes);
      if (_disposed) {
        renderer?.close();
        return;
      }
      if (renderer == null) {
        pdf = bytes;
        _done = true;
        notifyListeners();
        return;
      }
      _renderer = renderer;
      final (r, o) = await renderer.info();
      ratio = r;
      outline = o;
      pages = List.filled(renderer.pageCount, null);
      _done = true;
      notifyListeners();
      await _renderAll();
    } catch (e) {
      error = '$e';
      _done = true;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _renderAll() async {
    final store = FileStore.instance;
    while (!_disposed && ready < pages.length) {
      final order = [for (var k = _focus; k < pages.length; k++) k, for (var k = 0; k < _focus; k++) k];
      final next = order.firstWhere((k) => pages[k] == null, orElse: () => -1);
      if (next < 0) break;
      var jpeg = await store.cachedPage(bucket, path, next, width);
      if (jpeg == null) {
        jpeg = await _renderer!.render(next, width);
        unawaited(store.storePage(bucket, path, next, width, jpeg));
      }
      if (_disposed) return;
      pages[next] = jpeg;
      notifyListeners();
    }
    _renderer?.close();
    _renderer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _renderer?.close();
    super.dispose();
  }
}
