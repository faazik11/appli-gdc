import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models.dart';
import '../platform/device_files.dart';
import '../platform/recorder.dart';
import '../services/agenda.dart';
import '../services/workshop.dart';
import '../theme.dart';
import '../widgets/recording_markers.dart';
import '../widgets/ui.dart';
import 'recordings_screen.dart';

/// Enregistreur : écran toujours allumé, durée, niveau du micro, notes pendant la répétition.
class RecorderScreen extends StatefulWidget {
  final WorkBackend backend;
  final AgendaBackend agenda;

  const RecorderScreen({super.key, required this.backend, required this.agenda});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

enum _State { ready, recording, paused, saving }

class _RecorderScreenState extends State<RecorderScreen> {
  final _recorder = Recorder();
  final _watch = Stopwatch();
  final _notes = TextEditingController();
  Timer? _ticker;
  _State _state = _State.ready;
  String _mime = 'audio/webm';
  DateTime? _startedAt;
  ChoirEvent? _event;
  double _level = 0;
  String? _error;
  RecorderStatus _status = const RecorderStatus();
  bool _healing = false;
  final _markers = <RecordingMarker>[];

  /// Secondes réellement enregistrées (sans les moments coupés par le téléphone).
  int get _recordedSeconds => (_watch.elapsed.inSeconds - _recorder.status().lostSeconds).clamp(0, 1 << 30);

  Future<void> _addMarker() async {
    final seconds = _recordedSeconds;
    final songs = await markerSuggestions(eventSongIds: _event?.songIds ?? const []);
    if (!mounted) return;
    final label = await askMarkerLabel(context, seconds: seconds, pinned: songs.pinned, all: songs.all);
    if (label == null || !mounted) return;
    setState(() => _markers.add(RecordingMarker(seconds: seconds, label: label)));
  }

  @override
  void initState() {
    super.initState();
    _findTodaysRehearsal();
  }

  /// Rattache automatiquement l'enregistrement à la répétition du jour, s'il y en a une.
  Future<void> _findTodaysRehearsal() async {
    try {
      final now = DateTime.now();
      final events = await widget.agenda.events();
      final today = events.where((e) =>
          e.startsAt.year == now.year && e.startsAt.month == now.month && e.startsAt.day == now.day);
      final e = today.where((e) => e.isRehearsal).firstOrNull ?? today.firstOrNull;
      if (mounted) setState(() => _event = e);
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_state == _State.recording || _state == _State.paused) _recorder.stop();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _mime = await _recorder.start();
    } catch (e) {
      setState(() => _error = 'Micro inaccessible. Autorise l\'accès au micro pour cette appli puis réessaie.');
      return;
    }
    WakelockPlus.enable().catchError((_) {});
    _startedAt = DateTime.now();
    _watch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!mounted) return;
      setState(() {
        _level = _state == _State.recording ? _recorder.level() : 0;
        _status = _recorder.status();
      });
    });
    setState(() {
      _state = _State.recording;
      _error = null;
    });
  }

  void _togglePause() {
    if (_state == _State.recording) {
      _recorder.pause();
      _watch.stop();
      setState(() => _state = _State.paused);
    } else if (_state == _State.paused) {
      _recorder.resume();
      _watch.start();
      setState(() => _state = _State.recording);
    }
  }

  Future<void> _stop() async {
    setState(() => _state = _State.saving);
    _ticker?.cancel();
    _watch.stop();
    final sessionId = _recorder.sessionId;
    final lost = _recorder.status().lostSeconds;
    final parts = await _recorder.stop();
    WakelockPlus.disable().catchError((_) {});
    if (parts.every((p) => p.bytes.isEmpty)) {
      setState(() {
        _state = _State.ready;
        _error = 'L\'enregistrement est vide.';
      });
      return;
    }
    // 1. Gardé sur le téléphone d'abord : rien n'est perdu si le réseau coupe.
    final kept = await keepRecordedParts(
      parts,
      mime: _mime,
      eventId: _event?.id,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      durationSeconds: (_watch.elapsed.inSeconds - lost).clamp(1, 1 << 30),
      markers: _markers,
    );
    if (sessionId != null) await Recorder.clearDraft(sessionId);
    // 2. Puis envoyé pour tout le groupe.
    String message;
    try {
      for (final p in kept) {
        await PendingRecordings.send(widget.backend, p);
      }
      message = 'Répétition enregistrée et disponible pour tout le groupe.';
    } catch (_) {
      message = 'Pas de connexion : l\'enregistrement est gardé sur ce téléphone. Envoie-le depuis la page Répétitions.';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.pop(context, true);
  }

  Future<void> _heal() async {
    setState(() => _healing = true);
    final ok = await _recorder.heal();
    if (!mounted) return;
    setState(() {
      _healing = false;
      _status = _recorder.status();
      _error = ok ? null : 'Le micro ne répond plus. Arrête l\'enregistrement (ce qui a été enregistré est gardé) puis relance-le.';
    });
  }

  /// Avertit quand le téléphone a coupé l'enregistrement (écran verrouillé, appel, appli quittée).
  Widget _cutBanner() {
    final s = _status;
    final active = _state == _State.recording || _state == _State.paused;
    if (!active || (s.ok && s.cuts == 0)) return const SizedBox.shrink();
    final minutes = (s.lostSeconds / 60).round();
    final lost = s.lostSeconds < 60 ? 'moins d\'une minute' : '$minutes min';
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: s.ok ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE65100).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.ok ? Colors.white24 : Colors.orangeAccent),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded, color: s.ok ? AppColors.goldLight : Colors.orangeAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.ok
                  ? 'Le téléphone a coupé l\'enregistrement ${s.cuts == 1 ? 'une fois' : '${s.cuts} fois'} '
                      '($lost sans son). Il a repris : le reste est bien enregistré.'
                  : 'Enregistrement coupé par le téléphone (écran verrouillé ou appli quittée). '
                      'Touche « Reprendre » pour continuer.',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white),
            ),
          ),
        ]),
        if (!s.ok) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
            onPressed: _healing ? null : _heal,
            icon: const Icon(Icons.mic_rounded),
            label: const Text('Reprendre l\'enregistrement'),
          ),
        ],
      ]),
    );
  }

  String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final active = _state == _State.recording || _state == _State.paused;
    final now = _startedAt ?? DateTime.now();
    return PopScope(
      canPop: !active && _state != _State.saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_state == _State.saving) return;
        final stop = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: const Text('Arrêter et enregistrer la répétition ?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuer')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Arrêter')),
            ],
          ),
        );
        if (stop == true) _stop();
      },
      child: Scaffold(
        backgroundColor: AppColors.aubergine,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: Colors.white),
          title: const Text('Enregistrer'),
        ),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 32), children: [
            ContentWidth(
              maxWidth: 560,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(recordingTitle(now, null),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 24, color: Colors.white)),
                if (_event != null)
                  Text('Rattachée à : ${_event!.displayTitle} de ${DateFormat('HH:mm').format(_event!.startsAt)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.goldLight)),
                const SizedBox(height: 28),
                Text(_clock(_watch.elapsed),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 52, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(height: 12),
                // Niveau du micro
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: (_level * 1.6).clamp(0, 1).toDouble(),
                    color: _level > 0.9 ? Colors.redAccent : AppColors.gold,
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(height: 28),
                if (_state == _State.saving)
                  const Column(children: [
                    CircularProgressIndicator(color: AppColors.gold),
                    SizedBox(height: 12),
                    Text('Envoi de l\'enregistrement…', style: TextStyle(fontFamily: 'Poppins', color: Colors.white)),
                  ])
                else
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (active) ...[
                      IconButton.filledTonal(
                        iconSize: 30,
                        tooltip: _state == _State.paused ? 'Reprendre' : 'Pause',
                        icon: Icon(_state == _State.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                        onPressed: _togglePause,
                      ),
                      const SizedBox(width: 24),
                    ],
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          backgroundColor: const Color(0xFFD32F2F),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: !Recorder.supported ? null : (active ? _stop : _start),
                        child: Icon(active ? Icons.stop_rounded : Icons.fiber_manual_record_rounded, size: 48, color: Colors.white),
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 24),
                      IconButton.filledTonal(
                        iconSize: 30,
                        tooltip: 'Poser un repère (début d\'un chant)',
                        icon: const Icon(Icons.bookmark_add_rounded),
                        onPressed: _addMarker,
                      ),
                    ],
                  ]),
                const SizedBox(height: 10),
                Text(
                  !Recorder.supported
                      ? 'L\'enregistrement n\'est pas disponible sur cet appareil.'
                      : switch (_state) {
                          _State.ready => 'Pose le téléphone au milieu du groupe puis appuie pour démarrer.',
                          _State.recording => 'Enregistrement en cours · laisse l\'appli ouverte et ne verrouille pas le téléphone',
                          _State.paused => 'En pause',
                          _State.saving => '',
                        },
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: Colors.white.withValues(alpha: 0.75)),
                ),
                _cutBanner(),
                if (_markers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (final m in _markers)
                    Text('${markerClock(m.seconds)}  ${m.label}',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.goldLight)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.orangeAccent)),
                ],
                const SizedBox(height: 28),
                TextField(
                  controller: _notes,
                  minLines: 4,
                  maxLines: 12,
                  enabled: _state != _State.saving,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Points abordés',
                    labelStyle: const TextStyle(color: AppColors.goldLight),
                    hintText: 'Chants répétés : Vers la ville de Médine, Un seul regard',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    alignLabelWithHint: true,
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Garde sur le téléphone les fichiers d'un enregistrement (plusieurs après une pause ou une coupure),
/// qui seront lus à la suite comme un seul enregistrement.
Future<List<PendingRecording>> keepRecordedParts(
  List<RecordedPart> parts, {
  required String mime,
  String? eventId,
  String? notes,
  int? durationSeconds,
  List<RecordingMarker> markers = const [],
}) async {
  final files = parts.where((p) => p.bytes.isNotEmpty).toList();
  if (files.isEmpty) return [];
  final keys = [for (final (i, p) in files.indexed) 'enregistrement-${p.startedAt.millisecondsSinceEpoch}-$i'];
  for (final (i, p) in files.indexed.skip(1)) {
    await devicePut(keys[i], p.bytes);
  }
  return [
    await PendingRecordings.keep(
      files.first.bytes,
      PendingRecording(
        key: keys.first,
        recordedAt: files.first.startedAt,
        eventId: eventId,
        notes: notes,
        mimeType: mime,
        durationSeconds: durationSeconds ?? files.fold(0, (sum, p) => sum + p.seconds),
        markers: markers,
        extraFiles: [for (final (i, p) in files.indexed.skip(1)) RecordingPart(path: keys[i], seconds: p.seconds)],
      ),
    ),
  ];
}
