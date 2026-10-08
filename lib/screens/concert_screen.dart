import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/page_images.dart';
import '../theme.dart';
import '../widgets/pdf_pages_view.dart';

/// Mode concert : le livret en plein écran, page par page, écran toujours allumé.
/// Toutes les pages sont préparées en images à l'avance (et gardées sur l'appareil)
/// pour qu'elles tournent instantanément, même sur un long livret.
class ConcertScreen extends StatefulWidget {
  final String title;
  final String bucket;
  final String path;

  const ConcertScreen({super.key, required this.title, required this.bucket, required this.path});

  @override
  State<ConcertScreen> createState() => _ConcertScreenState();
}

class _ConcertScreenState extends State<ConcertScreen> {
  final _pageController = PageController();
  final _pdfController = PdfViewerController();
  PageImages? _images;
  int _page = 0;
  bool _controls = true;

  List<Uint8List?> get _pages => _images?.pages ?? const [];
  int get _ready => _images?.ready ?? 0;
  bool get _fallback => _images?.fallback ?? false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

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
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _decodeAround(_page);
  }

  @override
  void dispose() {
    _images?.dispose();
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Décode d'avance les pages voisines : le changement de page est immédiat.
  void _decodeAround(int page) {
    for (var k = page - 1; k <= page + 2; k++) {
      if (k >= 0 && k < _pages.length && _pages[k] != null) {
        precacheImage(MemoryImage(_pages[k]!), context);
      }
    }
  }

  void _turn(int delta) {
    if (_fallback) {
      delta > 0 ? _pdfController.nextPage() : _pdfController.previousPage();
      return;
    }
    final target = (_page + delta).clamp(0, max(0, _pages.length - 1)).toInt();
    // Changement instantané, même si on enchaîne les pages très vite.
    if (_pageController.hasClients) _pageController.jumpToPage(target);
  }

  Widget _viewer() {
    final error = _images?.error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Impossible d\'ouvrir le livret : $error',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    if (_fallback) {
      return SfPdfViewer.memory(
        _images!.pdf!,
        controller: _pdfController,
        pageLayoutMode: PdfPageLayoutMode.single,
        scrollDirection: PdfScrollDirection.horizontal,
        canShowScrollHead: false,
        canShowPaginationDialog: false,
        onTap: (_) => setState(() => _controls = !_controls),
        onPageChanged: (d) => setState(() => _page = d.newPageNumber - 1),
      );
    }
    if (_pages.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: AppColors.gold),
          SizedBox(height: 16),
          Text('Téléchargement du livret…', style: TextStyle(fontFamily: 'Poppins', color: Colors.white)),
        ]),
      );
    }
    return PageView.builder(
      controller: _pageController,
      itemCount: _pages.length,
      onPageChanged: (i) {
        setState(() => _page = i);
        _images?.focus = i;
        _decodeAround(i);
      },
      itemBuilder: (context, i) {
        final img = _pages[i];
        if (img == null) {
          return const Center(child: CircularProgressIndicator(color: AppColors.gold));
        }
        // Téléphone en paysage : la page prend toute la largeur et défile verticalement.
        final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
        return GestureDetector(
          onTap: () => setState(() => _controls = !_controls),
          child: InteractiveViewer(
            maxScale: 4,
            child: landscape
                ? SingleChildScrollView(
                    child: Image.memory(img, width: double.infinity, fit: BoxFit.fitWidth, gaplessPlayback: true),
                  )
                : Center(child: Image.memory(img, fit: BoxFit.contain, gaplessPlayback: true)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _fallback ? null : _pages.length;
    final preparing = !_fallback && _pages.isNotEmpty && _ready < _pages.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _turn(1),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _turn(1),
          const SingleActivator(LogicalKeyboardKey.space): () => _turn(1),
          const SingleActivator(LogicalKeyboardKey.pageDown): () => _turn(1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _turn(-1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _turn(-1),
          const SingleActivator(LogicalKeyboardKey.pageUp): () => _turn(-1),
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
        },
        child: Focus(
          autofocus: true,
          child: Stack(children: [
            Positioned.fill(child: _viewer()),
            // Zones de tapotement : gauche = page précédente, droite = page suivante.
            Positioned(left: 0, top: 80, bottom: 80, width: 70, child: GestureDetector(onTap: () => _turn(-1))),
            Positioned(right: 0, top: 80, bottom: 80, width: 70, child: GestureDetector(onTap: () => _turn(1))),
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controls,
                child: SafeArea(
                  child: Column(children: [
                    Container(
                      margin: const EdgeInsets.all(10),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(30)),
                      child: Row(children: [
                        IconButton(
                          tooltip: 'Quitter le mode concert',
                          color: Colors.white,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Text(widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                        if (!_fallback && _pages.isNotEmpty)
                          IconButton(
                            tooltip: 'Sommaire',
                            color: Colors.white,
                            icon: const Icon(Icons.toc_rounded),
                            onPressed: () async {
                              final page = await showOutline(context, _images!);
                              if (page != null && _pageController.hasClients) _pageController.jumpToPage(page);
                            },
                          ),
                        if (total != null && total > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text('${_page + 1} / $total',
                                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.goldLight)),
                          ),
                      ]),
                    ),
                    if (preparing)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(14)),
                        child: Column(children: [
                          Text('Préparation des pages : $_ready / ${_pages.length}',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: Colors.white)),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: _ready / _pages.length,
                            color: AppColors.gold,
                            backgroundColor: Colors.white24,
                          ),
                        ]),
                      ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text('Glisse ou touche les bords pour tourner les pages · touche le centre pour masquer',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
