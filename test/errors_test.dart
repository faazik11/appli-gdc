import 'dart:async';

import 'package:appli_gdc/services/errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('les erreurs techniques deviennent des phrases simples', () {
    expect(explain(Exception('ClientException: Failed to fetch')), startsWith('Pas de connexion'));
    expect(explain(TimeoutException('x')), startsWith('Pas de connexion'));
    expect(explain(const PostgrestException(message: 'new row violates row-level security policy', code: '42501')),
        startsWith('Ton rôle'));
    expect(explain(const PostgrestException(message: 'Seul un admin peut faire une sauvegarde', code: 'P0001')),
        'Seul un admin peut faire une sauvegarde');
    expect(explain(const FormatException('Ce fichier n\'est pas une sauvegarde.')), 'Ce fichier n\'est pas une sauvegarde.');
    expect(explain(StateError('bizarre')), 'Ça n\'a pas marché. Réessaie dans un instant.');
  });
}
