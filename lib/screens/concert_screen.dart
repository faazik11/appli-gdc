import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/repository.dart';
import '../theme.dart';

/// Mode concert : le livret en plein écran, page par page, écran toujours allumé.
class ConcertScreen extends StatefulWidget {
  final String title;
  final String bucket;
  final String path;

  /// Pour la démo : une URL déjà prête au lieu d'un lien signé.
  final Future<String> Function(String bucket, String path)? signUrl;

  const ConcertScreen({super.key, required this.title, required this.bucket, required this.path, this.signUrl});

  @override
  State<ConcertScreen> createState() => _ConcertScreenState();
}

class _ConcertScreenState extends State<ConcertScreen> {
  late final Future<String> _url = (widget.signUrl ?? Repository.instance.signedUrl)(widget.bucket, widget.path);
  final _controller = PdfViewerController();
  bool _controls = true;
  int _page = 1;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _turn(int delta) {
    if (delta > 0) {
      _controller.nextPage();
    } else {
      _controller.previousPage();
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Positioned.fill(
              child: FutureBuilder<String>(
                future: _url,
                builder: (context, snap) => snap.hasData
                    ? SfPdfViewerTheme(
                        data: const SfPdfViewerThemeData(backgroundColor: Colors.black),
                        child: SfPdfViewer.network(
                          snap.data!,
                          controller: _controller,
                          pageLayoutMode: PdfPageLayoutMode.single,
                          scrollDirection: PdfScrollDirection.horizontal,
                          canShowScrollHead: false,
                          canShowPaginationDialog: false,
                          enableDoubleTapZooming: true,
                          onTap: (_) => setState(() => _controls = !_controls),
                          onDocumentLoaded: (d) => setState(() => _pages = d.document.pages.count),
                          onPageChanged: (d) => setState(() => _page = d.newPageNumber),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator(color: AppColors.gold)),
              ),
            ),
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
                        if (_pages > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text('$_page / $_pages',
                                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.goldLight)),
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
