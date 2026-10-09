import 'dart:typed_data';

/// Enregistrement avec le micro : disponible dans l'appli web pour l'instant.
class Recorder {
  static bool get supported => false;
  Future<String> start() => throw UnsupportedError('Enregistrement indisponible sur cet appareil');
  double level() => 0;
  void pause() {}
  void resume() {}
  Future<Uint8List?> stop() async => null;
}
