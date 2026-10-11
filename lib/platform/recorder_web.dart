import 'dart:convert';
import 'dart:js_interop';

import 'recorder_io.dart' show RecordedPart, RecorderStatus, RecorderDraft;

export 'recorder_io.dart' show RecordedPart, RecorderStatus, RecorderDraft;

extension type _Part(JSObject _) implements JSObject {
  external JSUint8Array get bytes;
  external double get startedAt;
  external double get seconds;
}

extension type _GdcRecorder(JSObject _) implements JSObject {
  external bool supported();
  external JSPromise<JSString> start();
  external double level();
  external void pause();
  external void resume();
  external String status();
  external JSPromise<JSBoolean> heal();
  external String? sessionId();
  external JSPromise<JSArray<_Part>> stop();
  external JSPromise<JSString> drafts();
  external JSPromise<JSArray<_Part>> draftFiles(String id);
  external JSPromise<JSAny?> clearDraft(String id);
}

@JS('gdcRecorder')
external _GdcRecorder? get _rec;

List<RecordedPart> _parts(JSArray<_Part> list) => [
      for (final p in list.toDart)
        RecordedPart(p.bytes.toDart, DateTime.fromMillisecondsSinceEpoch(p.startedAt.round()), p.seconds.round()),
    ];

/// Enregistrement avec le micro du téléphone (MediaRecorder du navigateur).
/// Le son est gardé sur le téléphone au fur et à mesure et le micro est rebranché après une coupure.
class Recorder {
  static bool get supported => _rec?.supported() ?? false;

  /// Démarre et renvoie le type de fichier produit (audio/mp4 sur iPhone, audio/webm ailleurs).
  Future<String> start() async => (await _rec!.start().toDart).toDart;

  double level() => _rec?.level() ?? 0;
  void pause() => _rec?.pause();
  void resume() => _rec?.resume();

  RecorderStatus status() {
    final raw = _rec?.status();
    if (raw == null) return const RecorderStatus();
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return RecorderStatus(
      ok: m['ok'] as bool,
      cuts: (m['cuts'] as num).toInt(),
      lostSeconds: (m['lostSeconds'] as num).toInt(),
    );
  }

  /// Rebranche le micro après une coupure (à appeler depuis un toucher si l'iPhone l'exige).
  Future<bool> heal() async => (await _rec!.heal().toDart).toDart;

  String? get sessionId => _rec?.sessionId();

  Future<List<RecordedPart>> stop() async => _rec == null ? const [] : _parts(await _rec!.stop().toDart);

  static Future<List<RecorderDraft>> drafts() async {
    if (_rec == null) return const [];
    final list = jsonDecode((await _rec!.drafts().toDart).toDart) as List;
    return [
      for (final s in list.cast<Map<String, dynamic>>())
        RecorderDraft(s['id'] as String, (s['mime'] as String?) ?? 'audio/mp4',
            DateTime.fromMillisecondsSinceEpoch((s['startedAt'] as num).toInt())),
    ];
  }

  static Future<List<RecordedPart>> draftFiles(String id) async =>
      _rec == null ? const [] : _parts(await _rec!.draftFiles(id).toDart);

  static Future<void> clearDraft(String id) async => await _rec?.clearDraft(id).toDart;
}
