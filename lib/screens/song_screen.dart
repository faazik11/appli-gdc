import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models.dart';
import '../services/repository.dart';
import '../widgets/audio_player_bar.dart';

/// Écran de répétition : vidéo YouTube ou audio en haut, paroles en dessous.
class SongScreen extends StatefulWidget {
  final Song song;
  final bool canEdit;
  final VoidCallback onEdit;

  const SongScreen({super.key, required this.song, required this.canEdit, required this.onEdit});

  @override
  State<SongScreen> createState() => _SongScreenState();
}

enum _Source { youtube, audio }

class _SongScreenState extends State<SongScreen> {
  final _repo = Repository.instance;
  YoutubePlayerController? _youtube;
  Future<String>? _audioUrl;
  Future<String>? _pdfUrl;
  _Source? _source;
  bool _mediaVisible = true;

  @override
  void initState() {
    super.initState();
    final song = widget.song;
    final videoId =
        song.youtubeUrl == null ? null : YoutubePlayerController.convertUrlToId(song.youtubeUrl!);
    if (videoId != null) {
      _youtube = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        params: const YoutubePlayerParams(showFullscreenButton: true),
      );
      _source = _Source.youtube;
    }
    if (song.audioPath != null) {
      _audioUrl = _repo.signedUrl(Repository.audioBucket, song.audioPath!);
      _source ??= _Source.audio;
    }
    if (song.lyricsPdfPath != null) {
      _pdfUrl = _repo.signedUrl(Repository.lyricsBucket, song.lyricsPdfPath!);
    }
  }

  @override
  void dispose() {
    _youtube?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    return Scaffold(
      appBar: AppBar(
        title: Text(song.title),
        actions: [
          if (song.youtubeUrl != null)
            IconButton(
              tooltip: 'Ouvrir dans YouTube',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => launchUrl(Uri.parse(song.youtubeUrl!),
                  mode: LaunchMode.externalApplication),
            ),
          if (_source != null)
            IconButton(
              tooltip: _mediaVisible ? 'Masquer le lecteur' : 'Afficher le lecteur',
              icon: Icon(_mediaVisible ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() => _mediaVisible = !_mediaVisible),
            ),
          if (widget.canEdit)
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.pop(context);
                widget.onEdit();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_youtube != null && _audioUrl != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SegmentedButton<_Source>(
                segments: const [
                  ButtonSegment(value: _Source.youtube, label: Text('YouTube'), icon: Icon(Icons.smart_display)),
                  ButtonSegment(value: _Source.audio, label: Text('Audio'), icon: Icon(Icons.audiotrack)),
                ],
                selected: {_source!},
                onSelectionChanged: (s) {
                  if (s.first == _Source.audio) _youtube?.pauseVideo();
                  setState(() => _source = s.first);
                },
              ),
            ),
          // Le lecteur reste monté quand il est masqué, pour que le son continue.
          Offstage(
            offstage: !_mediaVisible,
            child: Column(children: [
              if (_youtube != null)
                Offstage(
                  offstage: _source != _Source.youtube,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: YoutubePlayer(controller: _youtube!),
                  ),
                ),
              if (_audioUrl != null && _source == _Source.audio)
                FutureBuilder<String>(
                  future: _audioUrl,
                  builder: (context, snap) => snap.hasData
                      ? AudioPlayerBar(url: snap.data!)
                      : const LinearProgressIndicator(),
                ),
            ]),
          ),
          if (song.notes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(song.notes!, style: Theme.of(context).textTheme.bodySmall),
            ),
          const Divider(height: 16),
          Expanded(
            child: _pdfUrl == null
                ? const Center(child: Text('Pas encore de PDF de paroles pour ce chant.'))
                : FutureBuilder<String>(
                    future: _pdfUrl,
                    builder: (context, snap) => snap.hasData
                        ? SfPdfViewer.network(snap.data!)
                        : const Center(child: CircularProgressIndicator()),
                  ),
          ),
        ],
      ),
    );
  }
}
