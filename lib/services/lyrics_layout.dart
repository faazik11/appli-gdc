import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'arabic_forms.dart';

/// Un morceau de ligne des paroles, tel qu'il est placé dans le PDF d'origine.
/// Une ligne à deux colonnes donne deux morceaux.
class LyricsSegment {
  /// Clé stable « page:ligne:morceau » (le PDF d'origine ne change jamais).
  final String key;
  final int page;
  final String text;
  final Rect box;

  /// Taille en points.
  final double size;
  final bool bold;

  LyricsSegment({
    required this.key,
    required this.page,
    required this.text,
    required this.box,
    required this.size,
    required this.bold,
  });

  bool get isRtl => isRtlText(text);
}

class LyricsPage {
  final Size size;
  final List<List<LyricsSegment>> lines;
  LyricsPage(this.size, this.lines);

  Iterable<LyricsSegment> get segments => lines.expand((l) => l);
}

bool _isArabic(int r) => (r >= 0x0600 && r <= 0x06FF) || (r >= 0xFB50 && r <= 0xFEFF);

bool isRtlText(String s) {
  var ar = 0, latin = 0;
  for (final r in s.runes) {
    if (_isArabic(r)) {
      ar++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F)) {
      latin++;
    }
  }
  return ar > latin;
}

/// Lettres « persanes » que Google Docs met à la place des lettres arabes.
const _fix = {0x06BE: 0x0647, 0x06C1: 0x0647, 0x06CC: 0x064A, 0x06A9: 0x0643};

String _normalize(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    // Le tatweel (ـ) est gardé : il fait partie du texte tel qu'il a été écrit.
    if (r == 0x200B || r == 0x20) continue;
    final f = arabicForms[r];
    if (f != null) {
      b.write(f);
    } else {
      b.writeCharCode(_fix[r] ?? r);
    }
  }
  return b.toString();
}

/// Signes posés sur ou sous une lettre (harakat, chadda…).
bool _isMarkRune(int r) => (r >= 0x064B && r <= 0x065F) || r == 0x0670 || (r >= 0x06D6 && r <= 0x06ED);

bool _isMark(String normalized) => normalized.isNotEmpty && normalized.runes.every(_isMarkRune);

class _Glyph {
  final String text; // normalisé
  final Rect box;
  final double size; // points (hauteur de la boîte du glyphe = taille de police)
  final bool bold;
  final List<String> marks = [];
  _Glyph(this.text, this.box, this.size, this.bold);
}

/// Lit le texte et sa mise en page dans un PDF de paroles.
List<LyricsPage> extractLyrics(Uint8List pdf) {
  final doc = PdfDocument(inputBytes: pdf);
  try {
    final extractor = PdfTextExtractor(doc);
    final pages = <LyricsPage>[];
    for (var p = 0; p < doc.pages.count; p++) {
      final size = doc.pages[p].size;
      final base = <_Glyph>[];
      final marks = <_Glyph>[];
      for (final line in extractor.extractTextLines(startPageIndex: p, endPageIndex: p)) {
        for (final word in line.wordCollection) {
          for (final g in word.glyphs) {
            final t = _normalize(g.text);
            if (t.isEmpty) continue;
            final glyph = _Glyph(t, g.bounds, g.bounds.height, g.fontStyle.contains(PdfFontStyle.bold));
            (_isMark(t) ? marks : base).add(glyph);
          }
        }
      }
      // Chaque signe va à la lettre qu'il surplombe.
      for (final m in marks) {
        final x = m.box.left;
        final my = m.box.center.dy;
        _Glyph? best;
        var score = double.infinity;
        for (final c in base) {
          final dy = (my - c.box.center.dy).abs();
          if (dy > c.size) continue;
          final inside = x >= c.box.left - 0.6 && x <= c.box.right + 0.6;
          final dx = inside ? max(0.0, x - c.box.left) * 0.1 : 5 + min((x - c.box.left).abs(), (x - c.box.right).abs());
          final s = dx + dy * 0.05;
          if (s < score) {
            score = s;
            best = c;
          }
        }
        best?.marks.add(m.text);
      }
      // Lignes : même ligne de base.
      base.sort((a, b) => a.box.bottom.compareTo(b.box.bottom));
      final rows = <List<_Glyph>>[];
      for (final g in base) {
        final row = rows.where((r) => (r.first.box.bottom - g.box.bottom).abs() < 0.35 * g.size).firstOrNull;
        if (row != null) {
          row.add(g);
        } else {
          rows.add([g]);
        }
      }
      rows.sort((a, b) => a.first.box.bottom.compareTo(b.first.box.bottom));
      final lines = <List<LyricsSegment>>[];
      for (final row in rows) {
        row.sort((a, b) => a.box.left.compareTo(b.box.left));
        // Morceaux : coupés sur les grands blancs (colonnes).
        final groups = <List<_Glyph>>[
          [row.first]
        ];
        for (var i = 1; i < row.length; i++) {
          if (row[i].box.left - row[i - 1].box.right > 0.9 * row[i].size) {
            groups.add([row[i]]);
          } else {
            groups.last.add(row[i]);
          }
        }
        final line = <LyricsSegment>[];
        for (final g in groups) {
          final rtl = g.where((c) => c.text.runes.any(_isArabic)).length > g.length / 2;
          final seq = rtl ? g.reversed.toList() : g;
          final b = StringBuffer();
          for (var i = 0; i < seq.length; i++) {
            if (i > 0) {
              final gap = rtl ? seq[i - 1].box.left - seq[i].box.right : seq[i].box.left - seq[i - 1].box.right;
              if (gap > 0.15 * seq[i].size) b.write(' ');
            }
            b
              ..write(seq[i].text)
              ..writeAll(seq[i].marks);
          }
          final text = b.toString().trim();
          if (text.isEmpty) continue;
          final sizes = <double, int>{};
          for (final c in g) {
            sizes[c.size] = (sizes[c.size] ?? 0) + 1;
          }
          final box = g.map((c) => c.box).reduce((a, c) => a.expandToInclude(c));
          line.add(LyricsSegment(
            key: '$p:${lines.length}:${line.length}',
            page: p,
            text: text,
            box: box,
            size: (sizes.entries.reduce((a, c) => c.value > a.value ? c : a).key * 10).roundToDouble() / 10,
            bold: g.where((c) => c.bold).length > g.length / 2,
          ));
        }
        if (line.isNotEmpty) lines.add(line);
      }
      pages.add(LyricsPage(size, lines));
    }
    return pages;
  } finally {
    doc.dispose();
  }
}

/// Polices pour réécrire les lignes corrigées (Arial, comme les PDF d'origine).
class LyricsFonts {
  final Uint8List regular, bold;
  LyricsFonts(this.regular, this.bold);
}

/// Une correction : nouveau texte (vide = ligne effacée) et sa couleur.
class LyricsEdit {
  final String text;
  final Color color;
  const LyricsEdit(this.text, this.color);
}

/// Le PDF d'origine avec les lignes corrigées : chaque ligne modifiée est
/// effacée (fond blanc) puis réécrite ; tout le reste est intact.
Future<Uint8List> applyLyricsEdits(
  Uint8List original,
  List<LyricsPage> pages,
  Map<String, LyricsEdit> edits,
  LyricsFonts fonts,
) async {
  final doc = PdfDocument(inputBytes: original);
  final cache = <String, PdfFont>{};
  PdfFont font(bool bold, double size) =>
      cache.putIfAbsent('$bold$size', () => PdfTrueTypeFont(bold ? fonts.bold : fonts.regular, size));
  try {
    for (final page in pages) {
      for (final line in page.lines) {
        for (final s in line) {
          final edit = edits[s.key];
          if (edit == null || edit.text == s.text) continue;
          final g = doc.pages[s.page].graphics;
          final pad = 0.12 * s.size;
          g.drawRectangle(
            brush: PdfBrushes.white,
            bounds: Rect.fromLTRB(s.box.left - 1.5, s.box.top - pad, s.box.right + 1.5, s.box.bottom + pad),
          );
          final text = edit.text.trim();
          if (text.isEmpty) continue;
          final rtl = isRtlText(text);
          final format = PdfStringFormat(
            textDirection: rtl ? PdfTextDirection.rightToLeft : PdfTextDirection.none,
            wordWrap: PdfWordWrapType.none,
          );
          final w = page.size.width;
          final centre = s.box.center.dx;
          final centred = line.length == 1 && (centre - w / 2).abs() < 0.06 * w;
          // Place disponible : la ligne entière si elle était centrée, sinon un peu plus que l'ancienne.
          final room = centred ? w - 60 : s.box.width * 1.15;
          var f = font(s.bold, s.size);
          final width = f.measureString(text, format: format).width;
          if (width > room) {
            f = font(s.bold, ((s.size * room / width).clamp(s.size * 0.6, s.size) * 10).floorToDouble() / 10);
          }
          final Rect box;
          if (centred) {
            final half = min(centre, w - centre);
            box = Rect.fromLTWH(centre - half, 0, 2 * half, 0);
            format.alignment = PdfTextAlignment.center;
          } else if (rtl) {
            box = Rect.fromLTWH(0, 0, s.box.right, 0);
            format.alignment = PdfTextAlignment.right;
          } else {
            box = Rect.fromLTWH(s.box.left, 0, w - s.box.left, 0);
            format.alignment = PdfTextAlignment.left;
          }
          final c = edit.color;
          g.drawString(
            text,
            f,
            brush: PdfSolidBrush(PdfColor((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round())),
            bounds: Rect.fromLTWH(box.left, s.box.bottom - f.height * 1.03, box.width, f.height * 1.6),
            format: format,
          );
        }
      }
    }
    return Uint8List.fromList(await doc.save());
  } finally {
    doc.dispose();
  }
}

/// Couleur du texte dans une zone d'une page rendue en image (RGBA, [scale] px par point).
Color sampleTextColor(Uint8List rgba, int width, int height, Rect box, double scale) {
  final x0 = (box.left * scale).floor().clamp(0, width - 1);
  final x1 = (box.right * scale).ceil().clamp(0, width - 1);
  final y0 = (box.top * scale).floor().clamp(0, height - 1);
  final y1 = (box.bottom * scale).ceil().clamp(0, height - 1);
  final dark = <(int, int, int, int)>[];
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final i = (y * width + x) * 4;
      final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      final lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
      if (lum < 170) dark.add((lum, r, g, b));
    }
  }
  if (dark.isEmpty) return const Color(0xFF000000);
  dark.sort((a, b) => a.$1.compareTo(b.$1));
  final core = dark.take(max(1, dark.length ~/ 3));
  var r = 0, g = 0, b = 0;
  for (final p in core) {
    r += p.$2;
    g += p.$3;
    b += p.$4;
  }
  final n = core.length;
  r ~/= n;
  g ~/= n;
  b ~/= n;
  // Gris foncé = noir (lissage des bords).
  if ((max(r, max(g, b)) - min(r, min(g, b))) < 40) return const Color(0xFF000000);
  return Color.fromARGB(255, r, g, b);
}
