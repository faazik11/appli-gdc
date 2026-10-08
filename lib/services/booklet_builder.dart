import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models.dart';

/// Assemble un livret PDF : couverture, sommaire, puis chaque partie
/// (page de titre de partie) suivie des PDF de paroles de ses chants.
class BookletBuilder {
  static const _a4 = Size(595, 842);
  static const _margin = 56.0;
  static const _tocLineHeight = 26.0;
  static const _tocTop = 150.0;

  // Couleurs de l'appli, en version claire pour rester imprimable.
  static final _aubergine = PdfColor(46, 26, 71);
  static final _gold = PdfColor(201, 162, 39);
  static final _goldDark = PdfColor(150, 115, 20);
  static final _ivory = PdfColor(250, 246, 239);
  static final _lavender = PdfColor(237, 230, 243);
  static final _lavenderDeep = PdfColor(222, 210, 233);
  static final _ink = PdfColor(58, 52, 66);

  /// Charge le PDF de paroles d'un chant à partir de son chemin de stockage.
  final Future<Uint8List> Function(String path) loadLyricsPdf;
  BookletBuilder(this.loadLyricsPdf);

  Future<List<int>> build({
    required String title,
    DateTime? eventDate,
    required List<BookletPart> parts,
    required Map<String, Song> songsById,
    void Function(String step)? onProgress,
  }) async {
    final regular = (await rootBundle.load('assets/fonts/Amiri-Regular.ttf')).buffer.asUint8List();
    final bold = (await rootBundle.load('assets/fonts/Amiri-Bold.ttf')).buffer.asUint8List();
    PdfFont font(double size, {bool isBold = false}) =>
        PdfTrueTypeFont(isBold ? bold : regular, size);

    // Entrées du sommaire, dans l'ordre du livret.
    final entries = <_TocEntry>[];
    for (final part in parts) {
      if (part.name.trim().isNotEmpty) entries.add(_TocEntry(part.name.trim(), isPart: true));
      for (final id in part.songIds) {
        final song = songsById[id];
        if (song != null) entries.add(_TocEntry(song.title));
      }
    }
    final linesPerTocPage = ((_a4.height - _tocTop - _margin - 20) / _tocLineHeight).floor();
    final tocPageCount = max(1, (entries.length / linesPerTocPage).ceil());

    final doc = PdfDocument();
    doc.pageSettings.margins.all = 0;
    doc.pageSettings.size = _a4;

    PdfPage newPage(Size size) {
      final section = doc.sections!.add();
      section.pageSettings.size = size;
      section.pageSettings.margins.all = 0;
      return section.pages.add();
    }

    // Couverture
    final cover = newPage(_a4);
    _decorateCover(cover);
    _drawCentered(cover, title, font(36, isBold: true), _a4.height / 2 - 80, color: _aubergine);
    _drawOrnament(cover, _a4.height / 2 + 5);
    if (eventDate != null) {
      _drawCentered(cover, DateFormat.yMMMMd('fr_FR').format(eventDate), font(18), _a4.height / 2 + 25, color: _goldDark);
    }
    _drawCentered(cover, 'Groupe de Chant Narbonne', font(14), _a4.height - 110, color: _aubergine);

    // Pages de sommaire (remplies une fois les numéros connus)
    final tocPages = [for (var i = 0; i < tocPageCount; i++) newPage(_a4)];
    for (final page in tocPages) {
      _decorateToc(page);
    }

    // Contenu
    var entryIndex = 0;
    var partNumber = 0;
    final pagesWithNumbers = <PdfPage>[];
    for (final part in parts) {
      if (part.name.trim().isNotEmpty) {
        final partPage = newPage(_a4);
        _decoratePart(partPage);
        _drawCentered(partPage, 'PARTIE ${++partNumber}', font(14, isBold: true), _a4.height / 2 - 70, color: _goldDark);
        _drawCentered(partPage, part.name.trim(), font(34, isBold: true), _a4.height / 2 - 40, color: _aubergine);
        _drawOrnament(partPage, _a4.height / 2 + 30);
        entries[entryIndex++].page = partPage;
        pagesWithNumbers.add(partPage);
      }
      for (final id in part.songIds) {
        final song = songsById[id];
        if (song == null) continue;
        final entry = entries[entryIndex++];
        onProgress?.call(song.title);
        if (song.lyricsPdfPath == null) {
          // Pas de PDF : page avec le titre seul, pour garder la place dans le livret.
          final page = newPage(_a4);
          _drawCentered(page, song.title, font(24, isBold: true), _margin + 20);
          _drawCentered(page, '(paroles à ajouter)', font(14), _margin + 70);
          entry.page = page;
          pagesWithNumbers.add(page);
          continue;
        }
        final bytes = await loadLyricsPdf(song.lyricsPdfPath!);
        final source = PdfDocument(inputBytes: bytes);
        for (var i = 0; i < source.pages.count; i++) {
          final sourcePage = source.pages[i];
          final page = newPage(sourcePage.size);
          page.graphics.drawPdfTemplate(sourcePage.createTemplate(), Offset.zero, sourcePage.size);
          if (i == 0) entry.page = page;
          pagesWithNumbers.add(page);
        }
        source.dispose();
      }
    }

    // Numéros de page (la couverture n'en a pas)
    int pageNumber(PdfPage page) => doc.pages.indexOf(page) + 1;
    final numberFont = font(11);
    for (final page in [...tocPages, ...pagesWithNumbers]) {
      final size = page.size;
      page.graphics.drawString(
        '${pageNumber(page)}',
        numberFont,
        brush: PdfSolidBrush(_aubergine),
        bounds: Rect.fromLTWH(0, size.height - 30, size.width, 20),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
    }

    // Sommaire avec liens cliquables et signets
    final tocTitleFont = font(26, isBold: true);
    final partFont = font(15, isBold: true);
    final songFont = font(13);
    for (var p = 0; p < tocPages.length; p++) {
      final page = tocPages[p];
      var y = _tocTop;
      _drawCentered(page, p == 0 ? 'Sommaire' : 'Sommaire (suite)', tocTitleFont, 48, color: _aubergine);
      final slice = entries.skip(p * linesPerTocPage).take(linesPerTocPage);
      for (final entry in slice) {
        final target = entry.page;
        if (target == null) continue;
        final indent = entry.isPart ? 0.0 : 18.0;
        final rtl = _isRtl(entry.title);
        final lineFont = entry.isPart ? partFont : songFont;
        final textWidth = _a4.width - 2 * _margin - indent - 50;
        if (entry.isPart) {
          // Bandeau doré pâle derrière le nom de la partie
          page.graphics.drawRectangle(
            brush: PdfSolidBrush(PdfColor(245, 236, 207)),
            bounds: Rect.fromLTWH(_margin - 8, y - 3, _a4.width - 2 * _margin + 16, _tocLineHeight - 4),
          );
          page.graphics.drawRectangle(
            brush: PdfSolidBrush(_gold),
            bounds: Rect.fromLTWH(_margin - 8, y - 3, 3, _tocLineHeight - 4),
          );
        } else if (!rtl) {
          // Points de conduite entre le titre et le numéro de page
          final titleWidth = min(lineFont.measureString(entry.title).width, textWidth);
          final from = _margin + indent + titleWidth + 6;
          final to = _a4.width - _margin - lineFont.measureString('${pageNumber(target)}').width - 6;
          if (to > from) {
            page.graphics.drawLine(
              PdfPen(_lavenderDeep, width: 1.2, dashStyle: PdfDashStyle.dot),
              Offset(from, y + 13),
              Offset(to, y + 13),
            );
          }
        }
        page.graphics.drawString(
          entry.title,
          lineFont,
          brush: PdfSolidBrush(entry.isPart ? _aubergine : _ink),
          bounds: Rect.fromLTWH(_margin + indent, y, textWidth, 0),
          format: PdfStringFormat(
            textDirection: rtl ? PdfTextDirection.rightToLeft : PdfTextDirection.none,
            alignment: rtl ? PdfTextAlignment.right : PdfTextAlignment.left,
            wordWrap: PdfWordWrapType.none,
          ),
        );
        page.graphics.drawString(
          '${pageNumber(target)}',
          lineFont,
          brush: PdfSolidBrush(entry.isPart ? _aubergine : _ink),
          bounds: Rect.fromLTWH(_a4.width - _margin - 50, y, 50, 0),
          format: PdfStringFormat(alignment: PdfTextAlignment.right),
        );
        page.annotations.add(PdfDocumentLinkAnnotation(
          Rect.fromLTWH(_margin, y, _a4.width - 2 * _margin, _tocLineHeight),
          PdfDestination(target),
        )..border = PdfAnnotationBorder(0));
        y += _tocLineHeight;
      }
    }

    // Signets (navigation dans la plupart des lecteurs PDF)
    PdfBookmark? currentPart;
    for (final entry in entries) {
      if (entry.page == null) continue;
      if (entry.isPart) {
        currentPart = doc.bookmarks.add(entry.title)..destination = PdfDestination(entry.page!);
      } else {
        final parent = currentPart;
        final bookmark = parent == null ? doc.bookmarks.add(entry.title) : parent.add(entry.title);
        bookmark.destination = PdfDestination(entry.page!);
      }
    }

    final out = await doc.save();
    doc.dispose();
    return out;
  }

  static bool _isRtl(String text) => RegExp(r'[֐-ࣿ]').hasMatch(text);

  static void _fill(PdfPage page, PdfColor color) => page.graphics.drawRectangle(
        brush: PdfSolidBrush(color),
        bounds: Rect.fromLTWH(0, 0, page.size.width, page.size.height),
      );

  /// Fond ivoire, double cadre doré et cercles pâles en coin.
  static void _decorateCover(PdfPage page) {
    final g = page.graphics;
    final w = page.size.width, h = page.size.height;
    _fill(page, _ivory);
    g.drawEllipse(Rect.fromLTWH(w - 260, -160, 420, 420), brush: PdfSolidBrush(_lavender));
    g.drawEllipse(Rect.fromLTWH(-170, h - 230, 380, 380), brush: PdfSolidBrush(_lavender));
    g.drawRectangle(pen: PdfPen(_gold, width: 2), bounds: Rect.fromLTWH(28, 28, w - 56, h - 56));
    g.drawRectangle(pen: PdfPen(_gold, width: 0.6), bounds: Rect.fromLTWH(36, 36, w - 72, h - 72));
  }

  /// Bandeau lavande en haut, filet doré dessous, fond ivoire.
  static void _decorateToc(PdfPage page) {
    final g = page.graphics;
    final w = page.size.width;
    _fill(page, _ivory);
    g.drawRectangle(brush: PdfSolidBrush(_lavender), bounds: Rect.fromLTWH(0, 0, w, 110));
    g.drawRectangle(brush: PdfSolidBrush(_gold), bounds: Rect.fromLTWH(0, 110, w, 3));
  }

  /// Fond ivoire, grand cercle lavande derrière le titre, filets dorés en haut et en bas.
  static void _decoratePart(PdfPage page) {
    final g = page.graphics;
    final w = page.size.width, h = page.size.height;
    _fill(page, _ivory);
    g.drawEllipse(Rect.fromLTWH(w / 2 - 190, h / 2 - 190, 380, 380), brush: PdfSolidBrush(_lavender));
    g.drawRectangle(brush: PdfSolidBrush(_gold), bounds: Rect.fromLTWH(0, 0, w, 6));
    g.drawRectangle(brush: PdfSolidBrush(_gold), bounds: Rect.fromLTWH(0, h - 6, w, 6));
  }

  /// Ornement : deux filets dorés et un losange au centre.
  static void _drawOrnament(PdfPage page, double y) {
    final g = page.graphics;
    final cx = page.size.width / 2;
    final pen = PdfPen(_gold, width: 1);
    g.drawLine(pen, Offset(cx - 90, y), Offset(cx - 12, y));
    g.drawLine(pen, Offset(cx + 12, y), Offset(cx + 90, y));
    g.drawPolygon([Offset(cx, y - 6), Offset(cx + 6, y), Offset(cx, y + 6), Offset(cx - 6, y)],
        brush: PdfSolidBrush(_gold));
  }

  static void _drawCentered(PdfPage page, String text, PdfFont font, double y, {PdfColor? color}) {
    final rtl = _isRtl(text);
    page.graphics.drawString(
      text,
      font,
      brush: color == null ? PdfBrushes.black : PdfSolidBrush(color),
      bounds: Rect.fromLTWH(_margin, y, page.size.width - 2 * _margin, 120),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.center,
        textDirection: rtl ? PdfTextDirection.rightToLeft : PdfTextDirection.none,
      ),
    );
  }
}

class _TocEntry {
  final String title;
  final bool isPart;
  PdfPage? page;

  _TocEntry(this.title, {this.isPart = false});
}
