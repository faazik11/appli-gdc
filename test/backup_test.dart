import 'dart:convert';
import 'dart:typed_data';

import 'package:appli_gdc/services/backup.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final export = {
    'format': 1,
    'created_at': '2026-10-12T19:00:00Z',
    'tables': {
      'songs': [
        {'id': 'a', 'title': 'Ya Rayah'},
      ],
      'events': <Map>[],
    },
    'files': [
      {'bucket': 'lyrics', 'path': '1_paroles.pdf', 'type': 'application/pdf'},
      {'bucket': 'materiel', 'path': 'tenues/2_photo.jpg', 'type': 'image/jpeg'},
      {'bucket': 'audio', 'path': 'perdu.mp3', 'type': 'audio/mpeg'},
    ],
  };
  final stored = {
    'lyrics/1_paroles.pdf': Uint8List.fromList([1, 2, 3]),
    'materiel/tenues/2_photo.jpg': Uint8List.fromList([4, 5]),
  };

  test('la sauvegarde contient les données, les fichiers et un mode d\'emploi', () async {
    final backup = Backup(
      export: () async => export,
      restoreRows: (_) async => {},
      download: (bucket, path) async => stored['$bucket/$path'] ?? (throw Exception('introuvable')),
      uploadIfMissing: (b, p, d, t) async => true,
    );
    final zip = ZipDecoder().decodeBytes(await backup.create());
    expect(jsonDecode(utf8.decode(zip.find('donnees.json')!.readBytes()!))['tables']['songs'][0]['title'], 'Ya Rayah');
    expect(zip.find('fichiers/lyrics/1_paroles.pdf')!.readBytes(), [1, 2, 3]);
    expect(zip.find('fichiers/materiel/tenues/2_photo.jpg')!.readBytes(), [4, 5]);
    final readme = utf8.decode(zip.find('LISEZ-MOI.txt')!.readBytes()!);
    expect(readme, contains('audio/perdu.mp3'));
    expect(readme, contains('Restaurer'));
  });

  test('la restauration renvoie les données et remet seulement les fichiers manquants', () async {
    Map<String, dynamic>? sentRows;
    final uploaded = <String, String?>{};
    final backup = Backup(
      export: () async => export,
      restoreRows: (data) async {
        sentRows = data;
        return {'songs': 1, 'events': 0};
      },
      download: (bucket, path) async => stored['$bucket/$path'] ?? (throw Exception('introuvable')),
      uploadIfMissing: (bucket, path, bytes, type) async {
        if (bucket == 'lyrics') return false; // déjà là
        uploaded['$bucket/$path'] = type;
        return true;
      },
    );
    final report = await backup.restore(await backup.create());
    expect(sentRows!['tables']['songs'][0]['id'], 'a');
    expect(report.rowsAdded, 1);
    expect(report.filesAdded, 1);
    expect(report.filesKept, 1);
    expect(uploaded, {'materiel/tenues/2_photo.jpg': 'image/jpeg'});
  });

  test('un autre fichier zip est refusé', () async {
    final backup = Backup(
      export: () async => export,
      restoreRows: (_) async => {},
      download: (b, p) async => Uint8List(0),
      uploadIfMissing: (b, p, d, t) async => true,
    );
    final other = ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.string('photo.txt', 'x')));
    expect(backup.restore(other), throwsA(isA<FormatException>()));
    expect(backup.restore(Uint8List.fromList([1, 2, 3])), throwsA(isA<FormatException>()));
  });
}
