import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/repository.dart';
import '../widgets/pdf_pages_view.dart';
import 'concert_screen.dart';

/// Affiche un PDF stocké (ex. un livret) avec un bouton pour le télécharger ou le partager.
class PdfViewScreen extends StatefulWidget {
  final String title;
  final String bucket;
  final String path;

  const PdfViewScreen({super.key, required this.title, required this.bucket, required this.path});

  @override
  State<PdfViewScreen> createState() => _PdfViewScreenState();
}

class _PdfViewScreenState extends State<PdfViewScreen> {
  final _viewer = GlobalKey<PdfPagesViewState>();

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
              builder: (_) => ConcertScreen(title: widget.title, bucket: widget.bucket, path: widget.path),
            )),
          ),
          IconButton(
            tooltip: 'Sommaire',
            icon: const Icon(Icons.toc),
            onPressed: () => _viewer.currentState?.openOutline(),
          ),
          IconButton(
            tooltip: 'Télécharger / partager',
            icon: const Icon(Icons.download),
            onPressed: () async => launchUrl(Uri.parse(await Repository.instance.signedUrl(widget.bucket, widget.path)),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: PdfPagesView(key: _viewer, bucket: widget.bucket, path: widget.path),
    );
  }
}
