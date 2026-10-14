import 'package:appli_gdc/models.dart';
import 'package:appli_gdc/services/workshop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('les suites sont lues après le fichier principal, dont la durée se déduit du total', () {
    final r = Recording.fromMap({
      'id': 'r1',
      'recorded_at': '2026-10-14T17:56:45Z',
      'audio_path': 'a.m4a',
      'duration_seconds': 2560 + 3000,
      'extra_parts': [
        {'path': 'b.m4a', 'seconds': 3000},
      ],
    });
    expect(r.parts.map((p) => p.path), ['a.m4a', 'b.m4a']);
    expect(r.parts.first.seconds, 2560);
  });

  test('un ancien enregistrement sans suite reste un seul fichier', () {
    final r = Recording.fromMap({'id': 'r2', 'recorded_at': '2026-10-10T14:01:01Z', 'audio_path': 'x.webm', 'duration_seconds': 60});
    expect(r.parts.length, 1);
    expect(r.parts.first.seconds, 60);
  });

  test('types et extensions des fichiers importés', () {
    expect(audioTypeOf('Nouvel enregistrement 3.M4A'), 'audio/mp4');
    expect(audioTypeOf('repet.mp3'), 'audio/mpeg');
    expect(audioExtensionOf(audioTypeOf('Rue de la Paix.qta')), 'm4a');
    expect(audioExtensionOf('audio/mp4'), 'm4a');
    expect(audioExtensionOf('audio/mpeg'), 'mp3');
    expect(audioExtensionOf('audio/webm;codecs=opus'), 'webm');
  });
}
