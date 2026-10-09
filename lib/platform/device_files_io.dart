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

Future<void> deviceDelete(String key) async {
  try {
    final f = await _file(key);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

Future<Uint8List> shrinkImage(Uint8List bytes, int maxSide) async => bytes;

/// Adresse locale pour lire des octets (audio) sans les retélécharger.
Future<String?> localUrl(Uint8List bytes, String mimeType) async {
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/lecture_${bytes.length}_${bytes.hashCode}');
    if (!await f.exists()) await f.writeAsBytes(bytes);
    return f.uri.toString();
  } catch (_) {
    return null;
  }
}

/// Rendu des pages en images : pas disponible hors navigateur (le lecteur PDF prend le relais).
Future<PageRenderer?> openPageRenderer(Uint8List pdf) async => null;

typedef OutlineEntry = ({String title, int page, int depth});

abstract class PageRenderer {
  int get pageCount;
  Future<(double, List<OutlineEntry>)> info();
  Future<Uint8List> render(int index, int width);
  void close();
}
