import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform/device_files.dart';

/// Garde la dernière version des listes (chants, agenda…) sur l'appareil
/// pour que l'appli reste utilisable sans internet.
class Offline {
  /// Vrai quand l'appli affiche des données enregistrées faute de connexion.
  static final isOffline = ValueNotifier(false);

  /// Compte utilisé hors connexion, quand la session n'a pas encore pu être rafraîchie.
  static String? userId;

  static String _key(String name) {
    final user = Supabase.instance.client.auth.currentUser?.id ?? userId ?? 'anonyme';
    return 'donnees/$user/$name';
  }

  static const _lastProfileKey = 'donnees/dernier-profil';

  /// Dernier profil connecté sur cet appareil (effacé à la déconnexion).
  static Future<Map<String, dynamic>?> lastProfile() async {
    final saved = await deviceGet(_lastProfileKey);
    if (saved == null || saved.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(saved)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLastProfile(Map<String, dynamic> row) =>
      devicePut(_lastProfileKey, Uint8List.fromList(utf8.encode(jsonEncode(row))));

  static Future<void> clearLastProfile() => devicePut(_lastProfileKey, Uint8List(0));

  /// Lit [fetch] en ligne et l'enregistre ; sans connexion, renvoie la copie enregistrée.
  static Future<List<Map<String, dynamic>>> rows(String name, Future<List<dynamic>> Function() fetch) async {
    try {
      final fresh = (await fetch().timeout(const Duration(seconds: 12))).cast<Map<String, dynamic>>();
      unawaited(devicePut(_key(name), Uint8List.fromList(utf8.encode(jsonEncode(fresh)))));
      isOffline.value = false;
      return fresh;
    } catch (e) {
      final saved = await deviceGet(_key(name));
      if (saved == null) rethrow;
      isOffline.value = true;
      return (jsonDecode(utf8.decode(saved)) as List).cast<Map<String, dynamic>>();
    }
  }
}
