import 'dart:js_interop';
import 'dart:typed_data';

extension type _GdcFiles(JSObject _) implements JSObject {
  external JSPromise<JSUint8Array?> get(String key);
  external JSPromise<JSBoolean> put(String key, JSUint8Array bytes);
  external JSPromise<JSNumber> open(JSUint8Array bytes);
  external int pageCount(int id);
  external JSPromise<JSUint8Array> render(int id, int index, int width);
  external void close(int id);
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

  Future<Uint8List> render(int index, int width) async => (await _f.render(_id, index, width).toDart).toDart;

  void close() => _f.close(_id);
}
