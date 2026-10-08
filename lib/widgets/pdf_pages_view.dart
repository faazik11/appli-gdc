import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../services/page_images.dart';

/// Sommaire d'un PDF (signets) ; renvoie l'index de la page choisie.
Future<int?> showOutline(BuildContext context, PageImages images) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (ctx, scroll) => images.outline.isEmpty
          ? ListView(controller: scroll, children: [
              for (var i = 0; i < images.pages.length; i++)
                ListTile(title: Text('Page ${i + 1}'), onTap: () => Navigator.pop(ctx, i)),
            ])
          : ListView(controller: scroll, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Sommaire', style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 24)),
              ),
              for (final e in images.outline)
                ListTile(
                  contentPadding: EdgeInsets.only(left: 20.0 + e.depth * 18, right: 20),
                  title: Text(e.title,
                      style: TextStyle(fontWeight: e.depth == 0 ? FontWeight.w600 : FontWeight.w400)),
                  trailing: Text('${e.page + 1}'),
                  onTap: () => Navigator.pop(ctx, e.page),
                ),
            ]),
    ),
  );
}

/// Lecteur de PDF (paroles, livrets) : pages préparées en images et gardées sur l'appareil,
/// défilement vertical sur toute la largeur, zoom à deux doigts.
class PdfPagesView extends StatefulWidget {
  final String bucket;
  final String path;

  const PdfPagesView({super.key, required this.bucket, required this.path});

  @override
  State<PdfPagesView> createState() => PdfPagesViewState();
}

class PdfPagesViewState extends State<PdfPagesView> {
  PageImages? _images;
  final _scroll = ScrollController();
  final _fallbackController = PdfViewerController();
  final _fallbackKey = GlobalKey<SfPdfViewerState>();
  double _extent = 0;

  static const _gap = 6.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_images == null) {
      final media = MediaQuery.of(context);
      _images = PageImages(
        bucket: widget.bucket,
        path: widget.path,
        width: PageImages.widthFor(media.size.width, media.size.height, media.devicePixelRatio),
      )..addListener(_changed);
      _images!.start();
      // Prépare en priorité les pages à l'écran.
      _scroll.addListener(() {
        if (_extent > 0) _images?.focus = (_scroll.offset / _extent).floor();
      });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Ouvre le sommaire et va à la page choisie.
  Future<void> openOutline() async {
    final images = _images;
    if (images == null) return;
    if (images.fallback) {
      _fallbackKey.currentState?.openBookmarkView();
      return;
    }
    if (images.pages.isEmpty) return;
    final page = await showOutline(context, images);
    if (page == null || !_scroll.hasClients) return;
    _images?.focus = page;
    _scroll.jumpTo((page * _extent).clamp(0, _scroll.position.maxScrollExtent));
  }

  @override
  void dispose() {
    _images?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = _images!;
    if (images.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Impossible d\'ouvrir le fichier.\n${images.error}', textAlign: TextAlign.center),
        ),
      );
    }
    if (images.fallback) return SfPdfViewer.memory(images.pdf!, key: _fallbackKey, controller: _fallbackController);
    if (images.pages.isEmpty) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(builder: (context, box) {
      // Toutes les pages ont la même hauteur : on peut aller directement à n'importe laquelle.
      _extent = box.maxWidth * images.ratio + _gap;
      return InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.zero,
          itemExtent: _extent,
          itemCount: images.pages.length,
          itemBuilder: (context, i) {
            final img = images.pages[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: _gap),
              child: img == null
                  ? Container(
                      color: Colors.white,
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  : Image.memory(img, width: box.maxWidth, fit: BoxFit.contain, gaplessPlayback: true),
            );
          },
        ),
      );
    });
  }
}
