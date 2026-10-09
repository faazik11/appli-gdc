import 'dart:js_interop';
import 'dart:typed_data';

import 'device_files_io.dart' show OutlineEntry;

export 'device_files_io.dart' show OutlineEntry;

extension type _GdcFiles(JSObject _) implements JSObject {
  external JSPromise<JSUint8Array?> get(String key);
  external JSPromise<JSBoolean> put(String key, JSUint8Array bytes);
  external JSPromise<JSNumber> open(JSUint8Array bytes);
  external int pageCount(int id);
  external JSPromise<_Info> info(int id);
  external JSPromise<JSUint8Array> render(int id, int index, int width);
  external void close(int id);
  external String objectUrl(JSUint8Array bytes, String type);
  external JSPromise<JSBoolean> remove(String key);
  external JSPromise<JSUint8Array> shrinkImage(JSUint8Array bytes, int maxSide);
}

extension type _Info(JSObject _) implements JSObject {
  external double get ratio;
  external JSArray<JSArray<JSAny>> get outline;
}

@JS('gdcFiles')
external _GdcFiles? get _files;

/// Fichiers gardés dans le navigateur du téléphone (Cache Storage).
Future<Uint8List?> deviceGet(String key) async {
  final files = _files;
  if (files == null) return null;
  try {
    return (await files.get(key).toDart)?.toDart;
  } catch (_) {
    return null;
  }
}

Future<void> devicePut(String key, Uint8List bytes) async {
  final files = _files;
  if (files == null) return;
  try {
    await files.put(key, bytes.toJS).toDart;
  } catch (_) {}
}

Future<void> deviceDelete(String key) async {
  try {
    await _files?.remove(key).toDart;
  } catch (_) {}
}

/// Réduit une photo avant de l'envoyer (plus léger, plus rapide à afficher).
Future<Uint8List> shrinkImage(Uint8List bytes, int maxSide) async {
  final files = _files;
  if (files == null) return bytes;
  try {
    return (await files.shrinkImage(bytes.toJS, maxSide).toDart).toDart;
  } catch (_) {
    return bytes;
  }
}

/// Adresse locale pour lire des octets (audio) sans les retélécharger.
Future<String?> localUrl(Uint8List bytes, String mimeType) async => _files?.objectUrl(bytes.toJS, mimeType);

/// Rend les pages d'un PDF en images avec PDF.js.
Future<PageRenderer?> openPageRenderer(Uint8List pdf) async {
  final files = _files;
  if (files == null) return null;
  final id = (await files.open(pdf.toJS).toDart).toDartInt;
  return PageRenderer._(files, id);
}

class PageRenderer {
  final _GdcFiles _f;
  final int _id;

  PageRenderer._(this._f, this._id);

  int get pageCount => _f.pageCount(_id);

  /// Hauteur / largeur de la première page, et signets (titre, page, niveau).
  Future<(double, List<OutlineEntry>)> info() async {
    final i = await _f.info(_id).toDart;
    return (
      i.ratio,
      [
        for (final e in i.outline.toDart)
          (
            title: (e.toDart[0] as JSString).toDart,
            page: (e.toDart[1] as JSNumber).toDartInt,
            depth: (e.toDart[2] as JSNumber).toDartInt,
          ),
      ],
    );
  }

  Future<Uint8List> render(int index, int width) async => (await _f.render(_id, index, width).toDart).toDart;

  void close() => _f.close(_id);
}
