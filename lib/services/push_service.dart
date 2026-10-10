import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform/push.dart';

/// Clé publique d'envoi (la clé privée reste sur le serveur).
const _vapidPublicKey = 'BM2DOq0o9Ey6ohfeAJn-z1PphMVWYmcF3ZWtPGCirIGEgDcWNskdhz21HX4A2ZyEvVcVtnhzez-BtyVqPPWErZw';

enum PushState { unsupported, off, on, blocked }

/// Notifications des répétitions, prestations et annonces sur cet appareil.
class PushService {
  PushService._();

  static final state = ValueNotifier<PushState>(_initial());

  static PushState _initial() {
    if (!DevicePush.supported) return PushState.unsupported;
    return switch (DevicePush.permission) {
      'denied' => PushState.blocked,
      _ => PushState.off,
    };
  }

  static SupabaseClient get _db => Supabase.instance.client;

  static Future<void> _save(String json) async {
    final s = jsonDecode(json) as Map<String, dynamic>;
    await _db.rpc('save_push_subscription', params: {
      'p_endpoint': s['endpoint'],
      'p_p256dh': s['p256dh'],
      'p_auth': s['auth'],
    });
  }

  /// Au lancement : si déjà autorisé, rattache l'abonnement au compte connecté.
  static Future<void> refresh() async {
    if (!DevicePush.supported) return;
    try {
      final sub = await DevicePush.current();
      if (sub != null) {
        await _save(sub);
        state.value = PushState.on;
      } else {
        state.value = _initial();
      }
    } catch (e) {
      debugPrint('notifications : $e');
    }
  }

  /// À appeler directement depuis un bouton. Renvoie l'état obtenu.
  static Future<PushState> enable() async {
    final sub = await DevicePush.subscribe(_vapidPublicKey);
    if (sub == null) {
      state.value = DevicePush.permission == 'denied' ? PushState.blocked : PushState.off;
      return state.value;
    }
    await _save(sub);
    state.value = PushState.on;
    // Petite notification de bienvenue pour vérifier que tout marche.
    () async {
      try {
        await _db.rpc('test_push');
      } catch (_) {}
    }();
    return state.value;
  }

  /// Coupe les notifications sur cet appareil (aussi à la déconnexion).
  static Future<void> disable() async {
    try {
      final endpoint = await DevicePush.unsubscribe();
      if (endpoint != null) await _db.from('push_subscriptions').delete().eq('endpoint', endpoint);
    } catch (e) {
      debugPrint('notifications : $e');
    }
    state.value = _initial();
  }
}
