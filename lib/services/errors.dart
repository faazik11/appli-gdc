import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Messages d'erreur en français simple, au lieu du texte technique des services.
String explain(Object e) {
  if (e is FormatException) return e.message;
  final text = '$e'.toLowerCase();
  if (e is TimeoutException ||
      text.contains('failed to fetch') ||
      text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('xmlhttprequest') ||
      text.contains('network')) {
    return 'Pas de connexion internet. Réessaie quand le réseau revient.';
  }
  if (text.contains('notallowederror')) {
    return 'Refusé par le téléphone. Autorise l\'appli dans les réglages du téléphone puis réessaie.';
  }
  if (e is AuthException || text.contains('jwt')) {
    return 'Ta connexion à l\'appli a expiré. Ferme l\'appli et rouvre-la.';
  }
  if (text.contains('row-level security') || text.contains('permission denied') || text.contains('42501')) {
    return 'Ton rôle ne permet pas de faire ça. Demande à un admin.';
  }
  if (text.contains('too large') || (e is StorageException && e.statusCode == '413')) {
    return 'Fichier trop lourd.';
  }
  // Messages écrits en français dans la base (ex. « Seul un admin peut… »).
  if (e is PostgrestException && e.code == 'P0001') return e.message;
  return 'Ça n\'a pas marché. Réessaie dans un instant.';
}

/// Zone de messages de l'appli, pour signaler une erreur depuis n'importe où.
final messenger = GlobalKey<ScaffoldMessengerState>();

/// Affiche « [what] : explication » en bas de l'écran.
void showError(Object e, {String what = 'Action impossible'}) =>
    messenger.currentState?.showSnackBar(SnackBar(content: Text('$what : ${explain(e)}')));

/// Lance [action] et signale l'échec au lieu de le taire ; renvoie true si tout s'est bien passé.
Future<bool> attempt(Future<void> Function() action, {String what = 'Action impossible'}) async {
  try {
    await action();
    return true;
  } catch (e) {
    showError(e, what: what);
    return false;
  }
}

DateTime _lastShown = DateTime(2000);

/// Filet de sécurité : une action en ligne qui échoue sans être gérée ailleurs prévient quand même.
/// Seules les erreurs des services en ligne s'affichent (pas les petits soucis internes),
/// et au plus une toutes les 4 secondes.
bool reportUncaught(Object e, StackTrace _) {
  final online = e is PostgrestException || e is StorageException || e is AuthException || e is TimeoutException ||
      '$e'.toLowerCase().contains('failed to fetch');
  if (online && DateTime.now().difference(_lastShown) > const Duration(seconds: 4)) {
    _lastShown = DateTime.now();
    showError(e);
  }
  return true;
}
