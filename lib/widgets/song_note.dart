import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models.dart';
import '../platform/recorder.dart';
import '../services/file_store.dart';
import '../services/repository.dart';
import '../services/workshop.dart';
import '../theme.dart';

/// Ouvre la note d'un chant : l'écouter, ou l'enregistrer s'il n'y en a pas encore.
/// [onChanged] reçoit le nouveau chemin (null si la note a été supprimée).
Future<void> showSongNote(
  BuildContext context, {
  required String songId,
  required String songTitle,
  required String? notePath,
  required bool canEdit,
  required ValueChanged<String?> onChanged,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: AppColors.aubergine,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _SongNoteSheet(
        songId: songId,
        songTitle: songTitle,
        notePath: notePath,
        canEdit: canEdit,
        onChanged: onChanged,
      ),
    );

class _SongNoteSheet extends StatefulWidget {
  final String songId;
  final String songTitle;
  final String? notePath;
  final bool canEdit;
  final ValueChanged<String?> onChanged;

  const _SongNoteSheet({
    required this.songId,
    required this.songTitle,
    required this.notePath,
    required this.canEdit,
    required this.onChanged,
  });

  @override
  State<_SongNoteSheet> createState() => _SongNoteSheetState();
}

enum _Mode { listen, ready, recording, review, saving }

class _SongNoteSheetState extends State<_SongNoteSheet> {
  final _player = AudioPlayer();
  final _recorder = Recorder();
  final _watch = Stopwatch();
  Timer? _ticker;
  late _Mode _mode = widget.notePath != null ? _Mode.listen : _Mode.ready;
  String? _path;
  String _mime = 'audio/webm';
  Uint8List? _take;
  double _level = 0;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = widget.notePath;
    _player.playerStateStream.listen((s) {
      final playing = s.playing && s.processingState != ProcessingState.completed;
      if (s.processingState == ProcessingState.completed) _player.pause();
      if (mounted && playing != _playing) setState(() => _playing = playing);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_mode == _Mode.recording) _discardRecording();
    _player.dispose();
    super.dispose();
  }

  /// Arrête le micro et oublie le brouillon, pour qu'il ne réapparaisse pas dans Répètes.
  Future<List<RecordedPart>> _stopRecorder() async {
    final session = _recorder.sessionId;
    final parts = await _recorder.stop();
    if (session != null) await Recorder.clearDraft(session);
    return parts;
  }

  void _discardRecording() => _stopRecorder().ignore();

  Future<void> _play(Future<String> Function() source) async {
    if (_playing) {
      await _player.pause();
      return;
    }
    try {
      await _player.setUrl(await source());
      await _player.seek(Duration.zero);
      _player.play();
      setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'Lecture impossible pour le moment.');
    }
  }

  Future<String> _savedUrl() => SupabaseWork().audioUrl(_path!);

  Future<String> _takeUrl() async {
    final url = await localUrl(_take!, _mime.split(';').first);
    if (url == null) throw StateError('lecture locale indisponible');
    return url;
  }

  Future<void> _start() async {
    await _player.stop();
    try {
      _mime = await _recorder.start();
    } catch (e) {
      setState(() => _error = 'Micro inaccessible. Autorise l\'accès au micro pour cette appli puis réessaie.');
      return;
    }
    _watch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (mounted) setState(() => _level = _recorder.level());
    });
    setState(() {
      _mode = _Mode.recording;
      _error = null;
    });
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    _watch.stop();
    final parts = await _stopRecorder();
    final bytes = parts.where((p) => p.bytes.isNotEmpty).map((p) => p.bytes).firstOrNull;
    if (!mounted) return;
    setState(() {
      _level = 0;
      _take = bytes;
      _mode = bytes == null ? _Mode.ready : _Mode.review;
      _error = bytes == null ? 'L\'enregistrement est vide, réessaie.' : null;
    });
  }

  Future<void> _save() async {
    await _player.stop();
    setState(() => _mode = _Mode.saving);
    final repo = Repository.instance;
    final type = _mime.split(';').first;
    final ext = type.contains('mp4') ? 'm4a' : (type.contains('ogg') ? 'ogg' : 'webm');
    try {
      final path = await repo.upload(Repository.notesBucket, 'note_${widget.songId}.$ext', _take!, type);
      await repo.setSongNote(widget.songId, path);
      final old = _path;
      if (old != null && old != path) repo.deleteFiles(Repository.notesBucket, [old]).ignore();
      // Gardée sur le téléphone pour l'écouter sans réseau.
      FileStore.instance.keep(Repository.notesBucket, path, _take!).ignore();
      widget.onChanged(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _take = null;
        _mode = _Mode.listen;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note enregistrée pour tout le groupe.')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _mode = _Mode.review;
          _error = 'Envoi impossible (connexion ?). Réessaie.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Supprimer la note de ce chant ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await _player.stop();
    final repo = Repository.instance;
    try {
      await repo.setSongNote(widget.songId, null);
      repo.deleteFiles(Repository.notesBucket, [_path!]).ignore();
      widget.onChanged(null);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'Suppression impossible (connexion ?).');
    }
  }

  String _clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _bigButton({required IconData icon, required Color color, required VoidCallback? onPressed, String? tooltip}) =>
      SizedBox(
        width: 88,
        height: 88,
        child: Tooltip(
          message: tooltip ?? '',
          child: FilledButton(
            style: FilledButton.styleFrom(shape: const CircleBorder(), backgroundColor: color, padding: EdgeInsets.zero),
            onPressed: onPressed,
            child: Icon(icon, size: 44, color: Colors.white),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white70);
    final white = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white38),
    );
    final children = switch (_mode) {
      _Mode.listen => [
          _bigButton(
            icon: _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
            color: AppColors.gold,
            tooltip: _playing ? 'Arrêter' : 'Écouter la note',
            onPressed: () => _play(_savedUrl),
          ),
          const SizedBox(height: 10),
          Text(_playing ? 'Lecture…' : 'Touche pour écouter la note', style: label),
          if (widget.canEdit) ...[
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton.icon(
                style: white,
                onPressed: Recorder.supported ? _start : null,
                icon: const Icon(Icons.mic_rounded),
                label: const Text('Modifier'),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Supprimer'),
              ),
            ]),
          ],
        ],
      _Mode.ready || _Mode.recording => [
          Text(_clock(_watch.elapsed),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 40, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: (_level * 1.6).clamp(0, 1).toDouble(),
              color: _level > 0.9 ? Colors.redAccent : AppColors.gold,
              backgroundColor: Colors.white12,
            ),
          ),
          const SizedBox(height: 20),
          _bigButton(
            icon: _mode == _Mode.recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
            color: const Color(0xFFD32F2F),
            tooltip: _mode == _Mode.recording ? 'Arrêter' : 'Enregistrer',
            onPressed: !Recorder.supported ? null : (_mode == _Mode.recording ? _stop : _start),
          ),
          const SizedBox(height: 10),
          Text(
            !Recorder.supported
                ? 'L\'enregistrement n\'est pas disponible sur cet appareil.'
                : _mode == _Mode.recording
                    ? 'Chante ou joue la note, puis arrête.'
                    : 'Appuie pour enregistrer la note de départ.',
            textAlign: TextAlign.center,
            style: label,
          ),
          if (_mode == _Mode.ready && _path != null) ...[
            const SizedBox(height: 12),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: () => setState(() => _mode = _Mode.listen),
              child: const Text('Garder la note actuelle'),
            ),
          ],
        ],
      _Mode.review || _Mode.saving => [
          _bigButton(
            icon: _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
            color: AppColors.gold,
            tooltip: 'Réécouter',
            onPressed: _mode == _Mode.saving ? null : () => _play(_takeUrl),
          ),
          const SizedBox(height: 10),
          Text('Réécoute avant de valider (${_clock(_watch.elapsed)})', style: label),
          const SizedBox(height: 24),
          if (_mode == _Mode.saving)
            const CircularProgressIndicator(color: AppColors.gold)
          else
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton.icon(
                style: white,
                onPressed: () async {
                  await _player.stop();
                  setState(() {
                    _take = null;
                    _mode = _Mode.ready;
                    _watch.reset();
                  });
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Recommencer'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.aubergine),
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Valider'),
              ),
            ]),
        ],
    };
    return PopScope(
      canPop: _mode != _Mode.recording && _mode != _Mode.saving,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('Note du chant', style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 24, color: Colors.white)),
            Text(widget.songTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.goldLight)),
            const SizedBox(height: 24),
            ...children,
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.orangeAccent)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Notes des chants d'un livret, par titre (tel qu'il apparaît dans le sommaire du PDF).
/// Un chant sans note a la valeur null : il « couvre » ses pages sans proposer de note.
Map<String, String?> bookletNotes(Booklet booklet, List<Song> songs) {
  final byId = {for (final s in songs) s.id: s};
  return {
    for (final part in booklet.parts)
      for (final id in part.songIds)
        if (byId[id] != null) byId[id]!.title: byId[id]!.noteAudioPath,
  };
}

/// Chant affiché à la page [page] d'un livret : la dernière entrée du sommaire qui commence
/// avant ou sur cette page et qui est un chant du livret (les titres de parties sont ignorés).
String? songAtPage(List<OutlineEntry> outline, Set<String> songTitles, int page) {
  OutlineEntry? current;
  for (final e in outline) {
    if (e.page <= page && songTitles.contains(e.title) && (current == null || e.page >= current.page)) current = e;
  }
  return current?.title;
}

/// Garde les notes sur l'appareil pour les écouter sans réseau (mode concert).
void keepNotesOffline(Iterable<String?> paths) {
  for (final p in paths) {
    if (p != null) FileStore.instance.load(Repository.notesBucket, p).ignore();
  }
}

/// Bouton rond qui joue la note de départ d'un chant en un seul toucher (toucher encore pour arrêter).
class NoteButton extends StatefulWidget {
  final String path;
  final String songTitle;

  const NoteButton({super.key, required this.path, required this.songTitle});

  @override
  State<NoteButton> createState() => _NoteButtonState();
}

class _NoteButtonState extends State<NoteButton> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((s) {
      final playing = s.playing && s.processingState != ProcessingState.completed;
      if (s.processingState == ProcessingState.completed) _player.pause();
      if (mounted && playing != _playing) setState(() => _playing = playing);
    });
  }

  @override
  void didUpdateWidget(NoteButton old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _player.stop();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    try {
      await _player.setUrl(await SupabaseWork().audioUrl(widget.path));
      await _player.seek(Duration.zero);
      _player.play();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lecture de la note impossible pour le moment.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Material(
        color: _playing ? AppColors.gold : AppColors.aubergine.withValues(alpha: 0.75),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: _playing ? 'Arrêter la note' : 'Note de départ : ${widget.songTitle}',
          icon: Icon(_playing ? Icons.stop_rounded : Icons.music_note_rounded,
              color: _playing ? AppColors.aubergine : Colors.white),
          onPressed: _toggle,
        ),
      );
}
