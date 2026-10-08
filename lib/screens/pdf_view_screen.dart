import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/file_store.dart';
import '../services/repository.dart';
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
  late final Future<Uint8List> _bytes = FileStore.instance.load(widget.bucket, widget.path);
  final _viewer = GlobalKey<SfPdfViewerState>();

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
            onPressed: () => _viewer.currentState?.openBookmarkView(),
          ),
          IconButton(
            tooltip: 'Télécharger / partager',
            icon: const Icon(Icons.download),
            onPressed: () async => launchUrl(Uri.parse(await Repository.instance.signedUrl(widget.bucket, widget.path)),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snap) => snap.hasError
            ? Center(child: Text('Impossible d\'ouvrir le fichier : ${snap.error}'))
            : snap.hasData
                ? SfPdfViewer.memory(snap.data!, key: _viewer)
                : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
