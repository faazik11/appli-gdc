import 'package:appli_gdc/models.dart';
import 'package:appli_gdc/services/workshop.dart';
import 'package:appli_gdc/widgets/recording_markers.dart';
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

  test('repères : lus triés, gardés hors connexion, répartis entre les fichiers coupés', () {
    final r = Recording.fromMap({
      'id': 'r3',
      'recorded_at': '2026-10-15T18:00:00Z',
      'audio_path': 'a.m4a',
      'markers': [
        {'s': 750, 'label': 'Ave'},
        {'s': 30, 'label': 'Échauffement'},
      ],
    });
    expect(r.markers.map((m) => m.label), ['Échauffement', 'Ave']);
    expect(markerClock(750), '12:30');
    expect(markerClock(3725), '1:02:05');

    final pending = PendingRecording(
        key: 'k', recordedAt: _date, mimeType: 'audio/mp4', durationSeconds: 60,
        markers: const [RecordingMarker(seconds: 5, label: 'Ave')]);
    expect(PendingRecording.fromMap(pending.toMap()).markers.single.label, 'Ave');

    final split = markersForParts(
      const [RecordingMarker(seconds: 10, label: 'A'), RecordingMarker(seconds: 700, label: 'B')],
      [600, 400],
    );
    expect(split[0].map((m) => (m.seconds, m.label)), [(10, 'A')]);
    expect(split[1].map((m) => (m.seconds, m.label)), [(100, 'B')]);
  });

  test('repères : recherche de chant sans tenir compte des accents ni des majuscules', () {
    final titles = ['Prière du soir', 'Ave Maria', 'Ya Khayra al-Anam', 'Priere 2'];
    expect(searchTitles(titles, 'priere'), ['Prière du soir', 'Priere 2']);
    expect(searchTitles(titles, '  '), isEmpty);
    expect(searchTitles(List.generate(150, (i) => 'Chant $i'), 'chant').length, 6);
  });
}

final _date = DateTime(2026, 10, 15);
