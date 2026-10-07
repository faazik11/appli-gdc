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
    final linesPerTocPage = ((_a4.height - 2 * _margin - 60) / _tocLineHeight).floor();
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
    _drawCentered(cover, title, font(34, isBold: true), _a4.height / 2 - 60);
    if (eventDate != null) {
      _drawCentered(cover, DateFormat.yMMMMd('fr_FR').format(eventDate), font(18), _a4.height / 2 + 10);
    }

    // Pages de sommaire (remplies une fois les numéros connus)
    final tocPages = [for (var i = 0; i < tocPageCount; i++) newPage(_a4)];

    // Contenu
    var entryIndex = 0;
    final pagesWithNumbers = <PdfPage>[];
    for (final part in parts) {
      if (part.name.trim().isNotEmpty) {
        final partPage = newPage(_a4);
        _drawCentered(partPage, part.name.trim(), font(30, isBold: true), _a4.height / 2 - 30);
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
        brush: PdfBrushes.dimGray,
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
      var y = _margin;
      if (p == 0) {
        _drawCentered(page, 'Sommaire', tocTitleFont, y);
      }
      y += 60;
      final slice = entries.skip(p * linesPerTocPage).take(linesPerTocPage);
      for (final entry in slice) {
        final target = entry.page;
        if (target == null) continue;
        final indent = entry.isPart ? 0.0 : 18.0;
        final rtl = _isRtl(entry.title);
        final lineFont = entry.isPart ? partFont : songFont;
        final textWidth = _a4.width - 2 * _margin - indent - 50;
        page.graphics.drawString(
          entry.title,
          lineFont,
          brush: PdfBrushes.black,
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
          brush: PdfBrushes.black,
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

  static void _drawCentered(PdfPage page, String text, PdfFont font, double y) {
    final rtl = _isRtl(text);
    page.graphics.drawString(
      text,
      font,
      brush: PdfBrushes.black,
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
