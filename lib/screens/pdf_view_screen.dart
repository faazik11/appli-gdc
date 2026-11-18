import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/repository.dart';
import '../widgets/pdf_pages_view.dart';
import 'concert_screen.dart';

/// Affiche un PDF stocké (ex. un livret) avec un bouton pour le télécharger ou le partager.
class PdfViewScreen extends StatefulWidget {
  final String title;
  final String bucket;
  final String path;

  /// Notes de départ des chants, transmises au mode concert.
  final Map<String, String?> notes;

  const PdfViewScreen({super.key, required this.title, required this.bucket, required this.path, this.notes = const {}});

  @override
  State<PdfViewScreen> createState() => _PdfViewScreenState();
}

class _PdfViewScreenState extends State<PdfViewScreen> {
  final _viewer = GlobalKey<PdfPagesViewState>();

  // Livret lu pendant la répétition : l'écran reste allumé.
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Mode concert',
            icon: const Icon(Icons.fullscreen_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ConcertScreen(title: widget.title, bucket: widget.bucket, path: widget.path, notes: widget.notes),
            )).then((_) => WakelockPlus.enable().catchError((_) {})), // le mode concert l'a coupé en sortant
          ),
          IconButton(
            tooltip: 'Sommaire',
            icon: const Icon(Icons.toc_rounded),
            onPressed: () => _viewer.currentState?.openOutline(),
          ),
          IconButton(
            tooltip: 'Télécharger / partager',
            icon: const Icon(Icons.download_rounded),
            onPressed: () async => launchUrl(Uri.parse(await Repository.instance.signedUrl(widget.bucket, widget.path)),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: PdfPagesView(key: _viewer, bucket: widget.bucket, path: widget.path),
    );
  }
}
