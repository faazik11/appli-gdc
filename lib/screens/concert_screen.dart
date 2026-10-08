import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/file_store.dart';
import '../theme.dart';

/// Mode concert : le livret en plein écran, page par page, écran toujours allumé.
/// Toutes les pages sont préparées en images à l'avance (et gardées sur l'appareil)
/// pour qu'elles tournent instantanément, même sur un long livret.
class ConcertScreen extends StatefulWidget {
  final String title;
  final String bucket;
  final String path;

  const ConcertScreen({super.key, required this.title, required this.bucket, required this.path});

  @override
  State<ConcertScreen> createState() => _ConcertScreenState();
}

class _ConcertScreenState extends State<ConcertScreen> {
  final _pageController = PageController();
  final _pdfController = PdfViewerController();
  Uint8List? _pdf;
  PageRenderer? _renderer;
  bool _fallback = false;
  String? _error;
  List<Uint8List?> _pages = const [];
  int _page = 0;
  bool _controls = true;
  bool _disposed = false;

  int get _ready => _pages.where((p) => p != null).length;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _disposed = true;
    _renderer?.close();
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final pdf = await FileStore.instance.load(widget.bucket, widget.path);
      if (_disposed) return;
      final renderer = await openPageRenderer(pdf);
      if (_disposed) {
        renderer?.close();
        return;
      }
      if (renderer == null) {
        setState(() {
          _pdf = pdf;
          _fallback = true;
        });
        return;
      }
      _renderer = renderer;
      setState(() => _pages = List.filled(renderer.pageCount, null));
      await _renderAll();
    } catch (e) {
      if (!_disposed) setState(() => _error = 'Impossible d\'ouvrir le livret : $e');
    }
  }

  /// Largeur de rendu : celle de l'écran en pixels réels, arrondie pour réutiliser les pages gardées.
  int get _width {
    final media = MediaQuery.of(context);
    final px = max(media.size.width, media.size.height * 0.75) * media.devicePixelRatio;
    return ((px / 200).ceil() * 200).clamp(800, 1600);
  }

  Future<void> _renderAll() async {
    final width = _width;
    final store = FileStore.instance;
    var i = 0;
    while (!_disposed && _ready < _pages.length) {
      // On prépare d'abord autour de la page affichée.
      final next = [for (var k = _page; k < _pages.length; k++) k, for (var k = 0; k < _page; k++) k]
          .firstWhere((k) => _pages[k] == null, orElse: () => -1);
      if (next < 0) break;
      var jpeg = await store.cachedPage(widget.bucket, widget.path, next, width);
      if (jpeg == null) {
        jpeg = await _renderer!.render(next, width);
        unawaited(store.storePage(widget.bucket, widget.path, next, width, jpeg));
      }
      if (_disposed || !mounted) return;
      setState(() => _pages[next] = jpeg);
      if ((next - _page).abs() <= 2) _decodeAround(_page);
      if (++i % 8 == 0) await Future<void>.delayed(Duration.zero);
    }
    _renderer?.close();
    _renderer = null;
  }

  /// Décode d'avance les pages voisines : le changement de page est immédiat.
  void _decodeAround(int page) {
    for (var k = page - 1; k <= page + 2; k++) {
      if (k >= 0 && k < _pages.length && _pages[k] != null) {
        precacheImage(MemoryImage(_pages[k]!), context);
      }
    }
  }

  void _turn(int delta) {
    if (_fallback) {
      delta > 0 ? _pdfController.nextPage() : _pdfController.previousPage();
      return;
    }
    final target = (_page + delta).clamp(0, max(0, _pages.length - 1)).toInt();
    // Changement instantané, même si on enchaîne les pages très vite.
    if (_pageController.hasClients) _pageController.jumpToPage(target);
  }

  Widget _viewer() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    if (_fallback) {
      return SfPdfViewer.memory(
        _pdf!,
        controller: _pdfController,
        pageLayoutMode: PdfPageLayoutMode.single,
        scrollDirection: PdfScrollDirection.horizontal,
        canShowScrollHead: false,
        canShowPaginationDialog: false,
        onTap: (_) => setState(() => _controls = !_controls),
        onPageChanged: (d) => setState(() => _page = d.newPageNumber - 1),
      );
    }
    if (_pages.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: AppColors.gold),
          SizedBox(height: 16),
          Text('Téléchargement du livret…', style: TextStyle(fontFamily: 'Poppins', color: Colors.white)),
        ]),
      );
    }
    return PageView.builder(
      controller: _pageController,
      itemCount: _pages.length,
      onPageChanged: (i) {
        setState(() => _page = i);
        _decodeAround(i);
      },
      itemBuilder: (context, i) {
        final img = _pages[i];
        if (img == null) {
          return const Center(child: CircularProgressIndicator(color: AppColors.gold));
        }
        return GestureDetector(
          onTap: () => setState(() => _controls = !_controls),
          child: InteractiveViewer(
            maxScale: 4,
            child: Center(child: Image.memory(img, fit: BoxFit.contain, gaplessPlayback: true)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _fallback ? null : _pages.length;
    final preparing = !_fallback && _pages.isNotEmpty && _ready < _pages.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _turn(1),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _turn(1),
          const SingleActivator(LogicalKeyboardKey.space): () => _turn(1),
          const SingleActivator(LogicalKeyboardKey.pageDown): () => _turn(1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _turn(-1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _turn(-1),
          const SingleActivator(LogicalKeyboardKey.pageUp): () => _turn(-1),
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
        },
        child: Focus(
          autofocus: true,
          child: Stack(children: [
            Positioned.fill(child: _viewer()),
            // Zones de tapotement : gauche = page précédente, droite = page suivante.
            Positioned(left: 0, top: 80, bottom: 80, width: 70, child: GestureDetector(onTap: () => _turn(-1))),
            Positioned(right: 0, top: 80, bottom: 80, width: 70, child: GestureDetector(onTap: () => _turn(1))),
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controls,
                child: SafeArea(
                  child: Column(children: [
                    Container(
                      margin: const EdgeInsets.all(10),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(30)),
                      child: Row(children: [
                        IconButton(
                          tooltip: 'Quitter le mode concert',
                          color: Colors.white,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Text(widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                        if (total != null && total > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text('${_page + 1} / $total',
                                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.goldLight)),
                          ),
                      ]),
                    ),
                    if (preparing)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(14)),
                        child: Column(children: [
                          Text('Préparation des pages : $_ready / ${_pages.length}',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: Colors.white)),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: _ready / _pages.length,
                            color: AppColors.gold,
                            backgroundColor: Colors.white24,
                          ),
                        ]),
                      ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text('Glisse ou touche les bords pour tourner les pages · touche le centre pour masquer',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
