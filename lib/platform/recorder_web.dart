import 'dart:js_interop';
import 'dart:typed_data';

extension type _GdcRecorder(JSObject _) implements JSObject {
  external bool supported();
  external JSPromise<JSString> start();
  external double level();
  external void pause();
  external void resume();
  external JSPromise<JSUint8Array?> stop();
}

@JS('gdcRecorder')
external _GdcRecorder? get _rec;

/// Enregistrement avec le micro du téléphone (MediaRecorder du navigateur).
class Recorder {
  static bool get supported => _rec?.supported() ?? false;

  /// Démarre et renvoie le type de fichier produit (audio/mp4 sur iPhone, audio/webm ailleurs).
  Future<String> start() async => (await _rec!.start().toDart).toDart;

  double level() => _rec?.level() ?? 0;
  void pause() => _rec?.pause();
  void resume() => _rec?.resume();
  Future<Uint8List?> stop() async => (await _rec?.stop().toDart)?.toDart;
}
