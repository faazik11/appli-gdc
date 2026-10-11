import 'dart:typed_data';

/// Un fichier produit par l'enregistreur.
class RecordedPart {
  final Uint8List bytes;
  final DateTime startedAt;
  final int seconds;
  const RecordedPart(this.bytes, this.startedAt, this.seconds);
}

/// État pendant l'enregistrement : coupures (écran verrouillé, appli quittée…).
class RecorderStatus {
  final bool ok;
  final int cuts;
  final int lostSeconds;
  const RecorderStatus({this.ok = true, this.cuts = 0, this.lostSeconds = 0});
}

/// Enregistrement interrompu resté sur le téléphone.
class RecorderDraft {
  final String id;
  final String mime;
  final DateTime startedAt;
  const RecorderDraft(this.id, this.mime, this.startedAt);
}

/// Enregistrement avec le micro : disponible dans l'appli web pour l'instant.
class Recorder {
  static bool get supported => false;
  Future<String> start() => throw UnsupportedError('Enregistrement indisponible sur cet appareil');
  double level() => 0;
  void pause() {}
  void resume() {}
  RecorderStatus status() => const RecorderStatus();
  Future<bool> heal() async => true;
  String? get sessionId => null;
  Future<List<RecordedPart>> stop() async => const [];
  static Future<List<RecorderDraft>> drafts() async => const [];
  static Future<List<RecordedPart>> draftFiles(String id) async => const [];
  static Future<void> clearDraft(String id) async {}
}
