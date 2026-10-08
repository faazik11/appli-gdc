import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Fichiers gardés dans le dossier de l'appli (téléphone, ordinateur).
Future<File> _file(String key) async {
  final dir = await getApplicationSupportDirectory();
  final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return File('${dir.path}/fichiers/$safe');
}

Future<Uint8List?> deviceGet(String key) async {
  try {
    final f = await _file(key);
    return await f.exists() ? await f.readAsBytes() : null;
  } catch (_) {
    return null;
  }
}

Future<void> devicePut(String key, Uint8List bytes) async {
  try {
    final f = await _file(key);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  } catch (_) {}
}

/// Rendu des pages en images : pas disponible hors navigateur (le lecteur PDF prend le relais).
Future<PageRenderer?> openPageRenderer(Uint8List pdf) async => null;

abstract class PageRenderer {
  int get pageCount;
  Future<Uint8List> render(int index, int width);
  void close();
}
