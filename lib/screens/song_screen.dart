import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models.dart';
import '../services/file_store.dart';
import '../services/repository.dart';
import '../theme.dart';
import '../widgets/audio_player_bar.dart';

/// Écran de répétition : vidéo YouTube ou audio en haut, paroles en dessous.
class SongScreen extends StatefulWidget {
  final Song song;
  final Category? category;
  final bool canEdit;
  final VoidCallback onEdit;
  final Future<String> Function(String bucket, String path)? signUrl;

  const SongScreen({
    super.key,
    required this.song,
    this.category,
    required this.canEdit,
    required this.onEdit,
    this.signUrl,
  });

  @override
  State<SongScreen> createState() => _SongScreenState();
}

enum _Source { youtube, audio }

class _SongScreenState extends State<SongScreen> {
  final _repo = Repository.instance;
  YoutubePlayerController? _youtube;
  Future<String>? _audioUrl;
  Future<Uint8List>? _pdf;
  _Source? _source;
  bool _mediaVisible = true;
  // Mode « paroles seules » : choisi à la main, ou automatique en paysage sur téléphone.
  bool _focusRequested = false;
  bool _showControlsInLandscape = false;

  Future<String> _sign(String bucket, String path) =>
      (widget.signUrl ?? _repo.signedUrl)(bucket, path);

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
      _audioUrl = _sign(Repository.audioBucket, song.audioPath!);
      _source ??= _Source.audio;
    }
    if (song.lyricsPdfPath != null) {
      _pdf = FileStore.instance.load(Repository.lyricsBucket, song.lyricsPdfPath!);
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
    final theme = Theme.of(context);
    final style = CategoryStyle.of(widget.category?.name ?? '');
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 1000 && size.height >= 600;
    final phoneLandscape = size.width > size.height && size.height < 500;
    final focus = _focusRequested || (phoneLandscape && !_showControlsInLandscape);

    final header = Container(
      decoration: BoxDecoration(gradient: style.gradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTheme(
              data: const IconThemeData(color: Colors.white),
              child: Row(children: [
                const BackButton(color: Colors.white),
                const Spacer(),
                if (song.youtubeUrl != null)
                  IconButton(
                    tooltip: 'Ouvrir dans YouTube',
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () => launchUrl(Uri.parse(song.youtubeUrl!), mode: LaunchMode.externalApplication),
                  ),
                if (_source != null && !wide)
                  IconButton(
                    tooltip: _mediaVisible ? 'Masquer le lecteur' : 'Afficher le lecteur',
                    icon: Icon(_mediaVisible ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    onPressed: () => setState(() => _mediaVisible = !_mediaVisible),
                  ),
                if (_pdf != null)
                  IconButton(
                    tooltip: 'Paroles en plein écran',
                    icon: const Icon(Icons.fullscreen_rounded),
                    onPressed: () => setState(() {
                      _focusRequested = true;
                      _showControlsInLandscape = false;
                    }),
                  ),
                if (widget.canEdit)
                  IconButton(
                    tooltip: 'Modifier',
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onEdit();
                    },
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                  child: Icon(style.icon, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(song.title,
                        style: const TextStyle(fontFamily: 'DMSerifDisplay', fontFamilyFallback: ['Amiri'], color: Colors.white, fontSize: 26, height: 1.15)),
                    if (widget.category != null || song.tags.isNotEmpty)
                      Text([if (widget.category != null) widget.category!.name, ...song.tags].join(' · '),
                          style: TextStyle(fontFamily: 'Poppins', color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );

    final media = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_youtube != null && _audioUrl != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SegmentedButton<_Source>(
            segments: const [
              ButtonSegment(value: _Source.youtube, label: Text('Vidéo'), icon: Icon(Icons.smart_display_rounded)),
              ButtonSegment(value: _Source.audio, label: Text('Audio'), icon: Icon(Icons.headphones_rounded)),
            ],
            selected: {_source!},
            onSelectionChanged: (s) {
              if (s.first == _Source.audio) _youtube?.pauseVideo();
              setState(() => _source = s.first);
            },
          ),
        ),
      // Le lecteur reste monté quand il est masqué, pour que le son continue.
      if (_youtube != null)
        Offstage(
          offstage: _source != _Source.youtube,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: wide ? 420 : 260),
              child: YoutubePlayer(controller: _youtube!),
            ),
          ),
        ),
      if (_audioUrl != null && _source == _Source.audio)
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FutureBuilder<String>(
              future: _audioUrl,
              builder: (context, snap) => snap.hasData ? AudioPlayerBar(url: snap.data!) : const LinearProgressIndicator(),
            ),
          ),
        ),
      if (song.notes != null)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.sticky_note_2_rounded, size: 18, color: theme.colorScheme.tertiary),
            const SizedBox(width: 10),
            Expanded(child: Text(song.notes!, style: theme.textTheme.bodyMedium)),
          ]),
        ),
    ]);

    final lyrics = Card(
      clipBehavior: Clip.antiAlias,
      shape: focus ? const RoundedRectangleBorder() : null,
      margin: EdgeInsets.zero,
      child: _pdf == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Pas encore de PDF de paroles pour ce chant.', textAlign: TextAlign.center),
              ),
            )
          : FutureBuilder<Uint8List>(
              future: _pdf,
              builder: (context, snap) => snap.hasError
                  ? Center(child: Text('Impossible d\'ouvrir les paroles : ${snap.error}'))
                  : snap.hasData
                      ? SfPdfViewer.memory(snap.data!)
                      : const Center(child: CircularProgressIndicator()),
            ),
    );

    // En plein écran, le lecteur reste monté (caché) pour que la musique continue.
    final content = wide && _source != null && !focus
        ? Padding(
            padding: const EdgeInsets.all(20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: SingleChildScrollView(child: media)),
              const SizedBox(width: 20),
              Expanded(flex: 6, child: lyrics),
            ]),
          )
        : Padding(
            padding: focus ? EdgeInsets.zero : const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_source != null || song.notes != null)
                Offstage(
                  offstage: !_mediaVisible || focus,
                  child: Padding(padding: const EdgeInsets.only(bottom: 14), child: media),
                ),
              Expanded(child: lyrics),
            ]),
          );

    return Scaffold(
      body: Column(children: [
        if (!focus) header,
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: focus ? SafeArea(child: content) : content),
            if (focus)
              Positioned(
                top: 8,
                right: 8,
                child: SafeArea(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _focusButton(Icons.arrow_back_rounded, 'Retour', () => Navigator.pop(context)),
                    const SizedBox(width: 8),
                    _focusButton(Icons.fullscreen_exit_rounded, 'Afficher le lecteur', () => setState(() {
                          _focusRequested = false;
                          _showControlsInLandscape = true;
                        })),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _focusButton(IconData icon, String tooltip, VoidCallback onPressed) => Material(
        color: AppColors.aubergine.withValues(alpha: 0.75),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: Colors.white),
          onPressed: onPressed,
        ),
      );
}
