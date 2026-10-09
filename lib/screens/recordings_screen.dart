import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models.dart';
import '../platform/recorder.dart';
import '../services/agenda.dart';
import '../services/workshop.dart';
import '../theme.dart';
import '../widgets/audio_player_bar.dart';
import '../widgets/ui.dart';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Titre par défaut : « Répétition du mercredi 14 octobre ».
String recordingTitle(DateTime d, String? title) =>
    (title?.trim().isNotEmpty ?? false) ? title!.trim() : 'Répétition du ${DateFormat('EEEE d MMMM', 'fr_FR').format(d)}';

String formatDuration(int? seconds) {
  if (seconds == null) return '';
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
  if (m > 0) return '$m min';
  return '$s s';
}

/// Page « Répétitions » : tous les enregistrements, du plus récent au plus ancien.
class RecordingsScreen extends StatefulWidget {
  final WorkBackend backend;
  final AgendaBackend agenda;
  final bool canEdit;

  /// Ouvre directement l'enregistreur (raccourci « Enregistrer » de l'accueil).
  final bool startRecording;

  const RecordingsScreen({
    super.key,
    required this.backend,
    required this.agenda,
    required this.canEdit,
    this.startRecording = false,
  });

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<Recording>? _items;
  List<PendingRecording> _pending = const [];
  String? _error;
  String? _sending;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.startRecording) WidgetsBinding.instance.addPostFrameCallback((_) => _record());
  }

  Future<void> _load() async {
    final pending = await PendingRecordings.list();
    if (mounted) setState(() => _pending = pending);
    try {
      final items = await widget.backend.recordings();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _record() async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RecorderScreen(backend: widget.backend, agenda: widget.agenda),
      ),
    );
    if (done == true) _load();
  }

  Future<void> _send(PendingRecording p) async {
    setState(() => _sending = p.key);
    try {
      await PendingRecordings.send(widget.backend, p);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enregistrement envoyé.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Envoi impossible pour l\'instant ($e). Il reste gardé sur ce téléphone.')));
      }
    }
    if (mounted) setState(() => _sending = null);
    _load();
  }

  Future<void> _open(Recording r) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RecordingDetailScreen(recording: r, backend: widget.backend, canEdit: widget.canEdit)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    // Regroupement par mois
    final groups = <String, List<Recording>>{};
    for (final r in items ?? const <Recording>[]) {
      groups.putIfAbsent(_cap(DateFormat('MMMM y', 'fr_FR').format(r.recordedAt)), () => []).add(r);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Répétitions')),
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.fiber_manual_record_rounded),
              label: const Text('Enregistrer'),
              onPressed: _record,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
          ContentWidth(
            maxWidth: 760,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_pending.isNotEmpty) ...[
                const SectionHeader('À envoyer'),
                for (final p in _pending)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Card(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      child: ListTile(
                        leading: const Icon(Icons.cloud_upload_outlined),
                        title: Text(recordingTitle(p.recordedAt, p.title)),
                        subtitle: Text('${formatDuration(p.durationSeconds)} · gardé sur ce téléphone, pas encore en ligne'),
                        trailing: _sending == p.key
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : FilledButton(onPressed: _sending == null ? () => _send(p) : null, child: const Text('Envoyer')),
                      ),
                    ),
                  ),
              ],
              if (items == null)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: _error == null ? const CircularProgressIndicator() : Text('Chargement impossible.\n$_error', textAlign: TextAlign.center),
                  ),
                )
              else if (items.isEmpty)
                EmptyState(
                  icon: Icons.mic_none_rounded,
                  title: 'Aucun enregistrement',
                  message: widget.canEdit
                      ? 'Appuie sur « Enregistrer » au début de la répétition : elle sera datée automatiquement et disponible ici pour tout le groupe.'
                      : 'Les répétitions enregistrées par le chef de chœur apparaîtront ici.',
                )
              else
                for (final g in groups.entries) ...[
                  SectionHeader(g.key),
                  for (final r in g.value)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _open(r),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 56,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(14)),
                                child: Column(children: [
                                  Text(DateFormat('EEE', 'fr_FR').format(r.recordedAt).toUpperCase().replaceAll('.', ''),
                                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.goldLight, fontWeight: FontWeight.w600)),
                                  Text('${r.recordedAt.day}',
                                      style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 24, color: Colors.white, height: 1.1)),
                                ]),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(recordingTitle(r.recordedAt, r.title), style: theme.textTheme.titleMedium),
                                  const SizedBox(height: 2),
                                  Row(children: [
                                    Icon(Icons.schedule_rounded, size: 15, color: theme.colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(
                                      [DateFormat('HH:mm').format(r.recordedAt), formatDuration(r.durationSeconds)]
                                          .where((s) => s.isNotEmpty)
                                          .join(' · '),
                                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                  ]),
                                  if (r.notes != null) ...[
                                    const SizedBox(height: 6),
                                    Text(r.notes!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                                  ],
                                ]),
                              ),
                              const Icon(Icons.play_circle_rounded, size: 34, color: AppColors.aubergineLight),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Écoute d'une répétition et points abordés.
class RecordingDetailScreen extends StatefulWidget {
  final Recording recording;
  final WorkBackend backend;
  final bool canEdit;

  const RecordingDetailScreen({super.key, required this.recording, required this.backend, required this.canEdit});

  @override
  State<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends State<RecordingDetailScreen> {
  late final Future<String> _url = widget.backend.audioUrl(widget.recording.audioPath);
  late final _title = TextEditingController(text: widget.recording.title);
  late final _notes = TextEditingController(text: widget.recording.notes);
  bool _dirty = false;
  bool _saving = false;
  bool _changed = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.backend.updateRecording(widget.recording.id, title: _title.text, notes: _notes.text);
      _changed = true;
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Points abordés enregistrés.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Supprimer cet enregistrement pour tout le groupe ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.backend.deleteRecording(widget.recording);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recording;
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Répétition'),
          actions: [
            if (widget.canEdit)
              IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
          ],
        ),
        body: ListView(children: [
          ContentWidth(
            maxWidth: 760,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(recordingTitle(r.recordedAt, r.title), style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  '${_cap(DateFormat('EEEE d MMMM y \'à\' HH:mm', 'fr_FR').format(r.recordedAt))}'
                  '${r.durationSeconds == null ? '' : ' · ${formatDuration(r.durationSeconds)}'}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: FutureBuilder<String>(
                      future: _url,
                      builder: (context, snap) => snap.hasError
                          ? ListTile(leading: const Icon(Icons.error_outline), title: Text('Lecture impossible : ${snap.error}'))
                          : !snap.hasData
                              ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                              : AudioPlayerBar(
                                  url: snap.data!,
                                  duration: r.durationSeconds == null ? null : Duration(seconds: r.durationSeconds!),
                                ),
                    ),
                  ),
                ),
                const SectionHeader('Points abordés'),
                if (widget.canEdit) ...[
                  TextField(
                    controller: _title,
                    decoration: InputDecoration(labelText: 'Titre', hintText: recordingTitle(r.recordedAt, null)),
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    minLines: 5,
                    maxLines: 20,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Chants répétés : Vers la ville de Médine, Un seul regard',
                      alignLabelWithHint: true,
                    ),
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_rounded),
                      label: const Text('Enregistrer les notes'),
                      onPressed: _dirty && !_saving ? _save : null,
                    ),
                  ),
                ] else
                  Text(r.notes ?? 'Aucun point noté pour cette répétition.', style: theme.textTheme.bodyLarge),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

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
      setState(() => _error = 'Micro inaccessible. Autorise l\'accès au micro pour cette appli puis réessaie.\n($e)');
      return;
    }
    WakelockPlus.enable().catchError((_) {});
    _startedAt = DateTime.now();
    _watch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (mounted) setState(() => _level = _state == _State.recording ? _recorder.level() : 0);
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
    final bytes = await _recorder.stop();
    WakelockPlus.disable().catchError((_) {});
    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _state = _State.ready;
        _error = 'L\'enregistrement est vide.';
      });
      return;
    }
    final start = _startedAt ?? DateTime.now();
    // 1. Gardé sur le téléphone d'abord : rien n'est perdu si le réseau coupe.
    final pending = await PendingRecordings.keep(
      bytes,
      PendingRecording(
        key: 'enregistrement-${start.millisecondsSinceEpoch}',
        recordedAt: start,
        eventId: _event?.id,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        mimeType: _mime,
        durationSeconds: _watch.elapsed.inSeconds,
      ),
    );
    // 2. Puis envoyé pour tout le groupe.
    String message;
    try {
      await PendingRecordings.send(widget.backend, pending);
      message = 'Répétition enregistrée et disponible pour tout le groupe.';
    } catch (_) {
      message = 'Pas de connexion : l\'enregistrement est gardé sur ce téléphone. Envoie-le depuis la page Répétitions.';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.pop(context, true);
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
                    if (active) const SizedBox(width: 72),
                  ]),
                const SizedBox(height: 10),
                Text(
                  !Recorder.supported
                      ? 'L\'enregistrement n\'est pas disponible sur cet appareil.'
                      : switch (_state) {
                          _State.ready => 'Pose le téléphone au milieu du groupe puis appuie pour démarrer.',
                          _State.recording => 'Enregistrement en cours · garde l\'appli ouverte (l\'écran reste allumé)',
                          _State.paused => 'En pause',
                          _State.saving => '',
                        },
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: Colors.white.withValues(alpha: 0.75)),
                ),
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
