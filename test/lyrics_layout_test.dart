import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:appli_gdc/services/lyrics_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Petit PDF de paroles : un titre centré, une ligne française, une ligne à deux colonnes.
Future<Uint8List> _sample(Uint8List font) async {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 0;
  final page = doc.pages.add();
  final g = page.graphics;
  final w = page.getClientSize().width;
  void line(String text, double y, {double size = 14, double? left}) => g.drawString(
        text,
        PdfTrueTypeFont(font, size),
        bounds: left == null ? Rect.fromLTWH(0, y, w, 40) : Rect.fromLTWH(left, y, 200, 40),
        format: PdfStringFormat(alignment: left == null ? PdfTextAlignment.center : PdfTextAlignment.left),
      );
  line('Au paradis', 60, size: 20);
  line('Ma prière est fierté mon jeune est succès', 120);
  line('Premier couplet', 180, left: 60);
  line('Second couplet', 180, left: 330);
  final bytes = Uint8List.fromList(await doc.save());
  doc.dispose();
  return bytes;
}

void main() {
  final font = File('assets/fonts/Amiri-Regular.ttf').readAsBytesSync();

  test('lit les lignes et les colonnes', () async {
    final pages = extractLyrics(await _sample(font));
    final lines = pages.single.lines.map((l) => l.map((s) => s.text).toList()).toList();
    expect(lines, [
      ['Au paradis'],
      ['Ma prière est fierté mon jeune est succès'],
      ['Premier couplet', 'Second couplet'],
    ]);
    expect(pages.single.lines.first.single.size, closeTo(20, 0.2));
  });

  test('réécrit seulement la ligne corrigée', () async {
    final pdf = await _sample(font);
    final pages = extractLyrics(pdf);
    final target = pages.single.lines[1].single;
    final out = await applyLyricsEdits(
      pdf,
      pages,
      {target.key: const LyricsEdit('Ma prière est fierté mon jeûne est succès', Color(0xFF1C4587))},
      LyricsFonts(font, font),
    );
    final doc = PdfDocument(inputBytes: out);
    final text = PdfTextExtractor(doc).extractText();
    doc.dispose();
    expect(text, contains('jeûne'));
    expect(text, contains('Au paradis'));
    expect(text, contains('Second couplet'));
  });

  test('couleur de texte relevée sur la page', () {
    // 4 x 2 pixels : 2 pixels bleus foncés, le reste blanc.
    final rgba = Uint8List.fromList([
      ...[28, 69, 135, 255], ...[28, 69, 135, 255], ...[255, 255, 255, 255], ...[255, 255, 255, 255],
      ...[255, 255, 255, 255], ...[255, 255, 255, 255], ...[255, 255, 255, 255], ...[255, 255, 255, 255],
    ]);
    final c = sampleTextColor(rgba, 4, 2, const Rect.fromLTWH(0, 0, 4, 2), 1);
    expect((c.b * 255).round(), 135);
    expect(sampleTextColor(Uint8List(4 * 4)..fillRange(0, 16, 20), 2, 2, const Rect.fromLTWH(0, 0, 2, 2), 1),
        const Color(0xFF000000));
  });

  test('lettres arabes de présentation ramenées aux lettres de base', () {
    expect(isRtlText('الصبح بدا'), isTrue);
    expect(isRtlText('Au paradis'), isFalse);
  });
}
