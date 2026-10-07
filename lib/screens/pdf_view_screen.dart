import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/repository.dart';

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
  late final Future<String> _url = Repository.instance.signedUrl(widget.bucket, widget.path);
  final _viewer = GlobalKey<SfPdfViewerState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Sommaire',
            icon: const Icon(Icons.toc),
            onPressed: () => _viewer.currentState?.openBookmarkView(),
          ),
          IconButton(
            tooltip: 'Télécharger / partager',
            icon: const Icon(Icons.download),
            onPressed: () async =>
                launchUrl(Uri.parse(await _url), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _url,
        builder: (context, snap) => snap.hasData
            ? SfPdfViewer.network(snap.data!, key: _viewer)
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
