/// Notifications du téléphone : disponibles dans l'appli web pour l'instant.
class DevicePush {
  static bool get supported => false;
  static String get permission => 'unsupported';
  static Future<String?> subscribe(String publicKey) async => null;
  static Future<String?> current() async => null;
  static Future<String?> unsubscribe() async => null;
}
