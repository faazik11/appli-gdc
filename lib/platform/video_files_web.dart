import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

extension type _GdcVideo(JSObject _) implements JSObject {
  external JSPromise<JSNumber> pick();
  external String name(int id);
  external double size(int id);
  external String type(int id);
  external JSPromise<JSNumber> duration(int id);
  external JSPromise<JSNumber> upload(int id, String url, String type, JSFunction progress);
  external void forget(int id);
  external JSObject player(String url);
}

@JS('gdcVideo')
external _GdcVideo? get _video;

/// Vidéo choisie sur le téléphone, pas encore envoyée (elle n'est pas chargée en mémoire).
class PickedVideo {
  final Object handle;
  final String name;
  final int size;
  final String type;
  final int seconds;

  const PickedVideo({required this.handle, required this.name, required this.size, required this.type, this.seconds = 0});
}

Future<PickedVideo?> pickVideo() async {
  final v = _video;
  if (v == null) return null;
  final id = (await v.pick().toDart).toDartInt;
  if (id < 0) return null;
  return PickedVideo(
    handle: id,
    name: v.name(id),
    size: v.size(id).round(),
    type: v.type(id),
    seconds: (await v.duration(id).toDart).toDartInt,
  );
}

/// Envoie la vidéo au lien signé ; lève une erreur si Cloudflare refuse ou si la connexion coupe.
Future<void> uploadVideo(PickedVideo v, String url, String type, void Function(double) onProgress) async {
  final status = (await _video!.upload(v.handle as int, url, type, ((double f) => onProgress(f)).toJS).toDart).toDartInt;
  if (status == 0) throw Exception('network');
  if (status >= 300) throw Exception('Cloudflare R2 a répondu $status');
}

void forgetVideo(PickedVideo v) => _video?.forget(v.handle as int);

int _views = 0;

/// Lecteur vidéo du navigateur (plein écran et AirPlay fournis par le téléphone).
Widget videoPlayer(String url) {
  final type = 'gdc-video-${++_views}';
  ui_web.platformViewRegistry.registerViewFactory(type, (int _) => _video!.player(url));
  return HtmlElementView(viewType: type);
}
