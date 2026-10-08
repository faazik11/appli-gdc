import 'dart:typed_data';

import '../platform/device_files.dart';
import 'repository.dart';

export '../platform/device_files.dart' show PageRenderer, openPageRenderer;

/// Fichiers (paroles, livrets) téléchargés une fois puis gardés sur l'appareil.
/// Le chemin d'un fichier change à chaque nouveau dépôt, donc une copie gardée reste à jour.
class FileStore {
  FileStore._();
  static final instance = FileStore._();

  /// Remplaçable pour la démo hors ligne.
  Future<Uint8List> Function(String bucket, String path) download = Repository.instance.download;

  final _memory = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List>>{};

  String _key(String bucket, String path) => '$bucket/$path';

  Future<Uint8List> load(String bucket, String path) {
    final key = _key(bucket, path);
    final mem = _memory[key];
    if (mem != null) return Future.value(mem);
    return _pending[key] ??= () async {
      try {
        var bytes = await deviceGet(key);
        if (bytes == null) {
          bytes = await download(bucket, path);
          await devicePut(key, bytes);
        }
        _remember(key, bytes);
        return bytes;
      } finally {
        _pending.remove(key);
      }
    }();
  }

  /// Vrai si le fichier est déjà sur l'appareil.
  Future<bool> has(String bucket, String path) async =>
      _memory.containsKey(_key(bucket, path)) || await deviceGet(_key(bucket, path)) != null;

  /// Pages déjà préparées pour le mode concert.
  Future<Uint8List?> cachedPage(String bucket, String path, int index, int width) =>
      deviceGet('${_key(bucket, path)}#p$index@$width');

  Future<void> storePage(String bucket, String path, int index, int width, Uint8List jpeg) =>
      devicePut('${_key(bucket, path)}#p$index@$width', jpeg);

  // Quelques fichiers en mémoire pour rouvrir instantanément.
  void _remember(String key, Uint8List bytes) {
    _memory[key] = bytes;
    while (_memory.length > 6) {
      _memory.remove(_memory.keys.first);
    }
  }
}
