import 'dart:js_interop';

extension type _GdcPush(JSObject _) implements JSObject {
  external bool supported();
  external String permission();
  external JSPromise<JSString?> subscribe(String publicKey);
  external JSPromise<JSString?> current();
  external JSPromise<JSString?> unsubscribe();
}

@JS('gdcPush')
external _GdcPush? get _push;

/// Notifications du téléphone via le navigateur (Web Push).
class DevicePush {
  static bool get supported => _push?.supported() ?? false;

  /// 'default' (pas encore demandé), 'granted', 'denied' ou 'unsupported'.
  static String get permission => _push?.permission() ?? 'unsupported';

  /// Demande l'autorisation (à appeler pendant un toucher) ; renvoie l'abonnement en JSON.
  static Future<String?> subscribe(String publicKey) async => (await _push?.subscribe(publicKey).toDart)?.toDart;

  static Future<String?> current() async => (await _push?.current().toDart)?.toDart;

  static Future<String?> unsubscribe() async => (await _push?.unsubscribe().toDart)?.toDart;
}
