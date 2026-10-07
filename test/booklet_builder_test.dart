import 'dart:io';

import 'package:appli_gdc/models.dart';
import 'package:appli_gdc/services/booklet_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assemble couverture, sommaire, parties et chants', () async {
    await initializeDateFormatting('fr_FR');
    const songs = {
      'a': Song(id: 'a', title: 'Alléluia', categoryId: 1, lyricsPdfPath: 'alleluia'),
      'b': Song(id: 'b', title: 'Ave Maria', categoryId: 1, lyricsPdfPath: 'ave_maria'),
      'c': Song(id: 'c', title: 'Amazing Grace', categoryId: 4, lyricsPdfPath: 'amazing_grace'),
      'd': Song(id: 'd', title: 'طلع البدر علينا', categoryId: 2),
    };
    final bytes = await BookletBuilder(
      (path) => File('test/fixtures/$path.pdf').readAsBytes(),
    ).build(
      title: 'Mariage de Sarah et Karim',
      eventDate: DateTime(2026, 11, 14),
      parts: [
        BookletPart(name: 'Entrée', songIds: ['a', 'd']),
        BookletPart(name: 'Méditation', songIds: ['b', 'c']),
      ],
      songsById: songs,
    );
    Directory('build').createSync(recursive: true);
    File('build/test_booklet.pdf').writeAsBytesSync(bytes);

    final doc = PdfDocument(inputBytes: bytes);
    // couverture + sommaire + 2 pages de partie + 2 + 1 (sans PDF) + 1 + 1
    expect(doc.pages.count, 9);
    expect(doc.bookmarks.count, 2);
    expect(doc.bookmarks[0].count, 2);
    final toc = PdfTextExtractor(doc).extractText(startPageIndex: 1, endPageIndex: 1);
    expect(toc, contains('Sommaire'));
    expect(toc, contains('Amazing Grace'));
    doc.dispose();
  });
}
