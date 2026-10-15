import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../platform/recorder.dart';
import '../services/agenda.dart';
import '../services/errors.dart';
import '../services/repository.dart';
import '../services/workshop.dart';
import '../theme.dart';
import '../widgets/audio_player_bar.dart';
import '../widgets/recording_markers.dart';
import '../widgets/ui.dart';
import 'import_audio_screen.dart';
import 'recorder_screen.dart';
import 'tools_screen.dart';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Titre par défaut : « Répétition du mercredi 14 octobre ».
String recordingTitle(DateTime d, String? title) =>
    (title?.trim().isNotEmpty ?? false) ? title!.trim() : 'Répétition du ${DateFormat('EEEE d MMMM', 'fr_FR').format(d)}';

/// Chants à proposer pour un repère : ceux au programme de l'événement en raccourci
/// ([pinned]), tous les autres seulement par la recherche ([all]).
Future<({List<String> pinned, List<String> all})> markerSuggestions({String? eventId, List<String>? eventSongIds}) async {
  try {
    final songs = await Repository.instance.songs();
    var ids = eventSongIds ?? const <String>[];
    if (eventSongIds == null && eventId != null) {
      final row = await Supabase.instance.client.from('events').select('song_ids').eq('id', eventId).maybeSingle();
      ids = ((row?['song_ids'] as List?) ?? const []).cast<String>();
    }
    final pinned = [for (final id in ids) ...songs.where((s) => s.id == id).map((s) => s.title)];
    return (pinned: pinned, all: songs.map((s) => s.title).toList());
  } catch (_) {
    return (pinned: const <String>[], all: const <String>[]);
  }
}

String formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
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
    await _recoverInterrupted();
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
      if (mounted) setState(() => _error = explain(e));
    }
  }

  /// Enregistrement coupé net (appli fermée par le téléphone) : le son gardé au fur et à mesure
  /// est récupéré puis envoyé comme un enregistrement normal.
  static bool _recovering = false;

  Future<void> _recoverInterrupted() async {
    if (_recovering) return;
    _recovering = true;
    try {
      final drafts = await Recorder.drafts();
      var recovered = 0;
      for (final d in drafts) {
        final parts = await Recorder.draftFiles(d.id);
        final kept = await keepRecordedParts(parts, mime: d.mime, notes: 'Récupéré après une coupure de l\'appli.');
        await Recorder.clearDraft(d.id);
        for (final p in kept) {
          recovered++;
          try {
            await PendingRecordings.send(widget.backend, p);
          } catch (_) {}
        }
      }
      if (recovered > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Un enregistrement coupé en cours de route a été récupéré.')));
      }
    } catch (_) {
    } finally {
      _recovering = false;
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

  /// Audio enregistré sans l'appli (Dictaphone…) : nouvel enregistrement ou suite d'un existant.
  Future<void> _import() async {
    final audio = await pickAudio(context);
    if (audio == null || !mounted) return;
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ImportAudioScreen(
          backend: widget.backend,
          agenda: widget.agenda,
          audio: audio,
          recordings: _items ?? const [],
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Envoi impossible : ${explain(e)} Il reste gardé sur ce téléphone.')));
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

  /// Diapason et métronome, à portée de main pendant la répétition.
  Widget _tools(BuildContext context) {
    final tint = Theme.of(context).colorScheme.tertiary;
    Widget chip(IconData icon, String label, int tab) => ActionChip(
          avatar: Icon(icon, size: 18, color: tint),
          label: Text(label),
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ToolsScreen(initialTab: tab))),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        chip(Icons.tune_rounded, 'Diapason', 0),
        chip(Icons.timer_outlined, 'Métronome', 1),
      ]),
    );
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
      appBar: AppBar(title: const Text('Répétitions'), actions: [
        if (widget.canEdit)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Importer'),
              onPressed: _import,
            ),
          ),
      ]),
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
              _tools(context),
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
                      ? 'Appuie sur « Enregistrer » au début de la répétition : elle sera datée automatiquement et disponible ici pour tout le groupe. '
                          'Un audio enregistré ailleurs (Dictaphone…) s\'ajoute avec « Importer ».'
                      : 'Les répétitions enregistrées par les référents apparaîtront ici.',
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
                                      [
                                        DateFormat('HH:mm').format(r.recordedAt),
                                        formatDuration(r.durationSeconds),
                                        if (r.extraParts.isNotEmpty) '${r.extraParts.length + 1} parties',
                                      ]
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
  late Recording _rec = widget.recording;
  late Future<List<String>> _urls = _loadUrls();
  bool _adding = false;
  late final _title = TextEditingController(text: widget.recording.title);
  late final _notes = TextEditingController(text: widget.recording.notes);
  bool _dirty = false;
  bool _saving = false;
  bool _changed = false;
  GlobalKey<AudioPlayerBarState> _player = GlobalKey();

  Future<List<String>> _loadUrls() => Future.wait([for (final p in _rec.parts) widget.backend.audioUrl(p.path)]);

  void _replace(Recording r) {
    _changed = true;
    setState(() {
      _rec = r;
      _urls = _loadUrls();
      _player = GlobalKey();
      if (!_dirty) _notes.text = r.notes ?? '';
    });
  }

  Future<void> _run(Future<Recording> Function() action, String done) async {
    setState(() => _adding = true);
    try {
      _replace(await action());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible pour l\'instant : ${explain(e)}')));
    }
    if (mounted) setState(() => _adding = false);
  }

  /// Ajoute à la suite un audio importé ou un autre enregistrement de la liste.
  Future<void> _addNext() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: const Text('Importer un fichier audio'),
            subtitle: const Text('Enregistré avec Dictaphone ou un autre appareil'),
            onTap: () => Navigator.pop(ctx, 0),
          ),
          ListTile(
            leading: const Icon(Icons.merge_rounded),
            title: const Text('Ajouter un autre enregistrement'),
            subtitle: const Text('Déjà dans la liste des répétitions'),
            onTap: () => Navigator.pop(ctx, 1),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 0) {
      final audio = await pickAudio(context);
      if (audio == null || !mounted) return;
      await _run(() => appendAudio(widget.backend, _rec, audio), 'Audio ajouté à la suite.');
      return;
    }
    List<Recording> others;
    try {
      others = (await widget.backend.recordings()).where((r) => r.id != _rec.id).toList();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chargement impossible : ${explain(e)}')));
      return;
    }
    if (!mounted) return;
    final other = await showModalBottomSheet<Recording>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Quel enregistrement mettre à la suite ?', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (others.isEmpty) const ListTile(title: Text('Aucun autre enregistrement.')),
            for (final r in others)
              ListTile(
                leading: const Icon(Icons.mic_none_rounded),
                title: Text(recordingTitle(r.recordedAt, r.title)),
                subtitle: Text([
                  DateFormat('d MMM y \'à\' HH:mm', 'fr_FR').format(r.recordedAt),
                  formatDuration(r.durationSeconds),
                ].where((s) => s.isNotEmpty).join(' · ')),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ]),
        ),
      ),
    );
    if (other == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('« ${recordingTitle(other.recordedAt, other.title)} » sera lu à la suite de celui-ci '
            'et n\'apparaîtra plus séparément dans la liste. Ses points abordés sont ajoutés aux tiens.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fusionner')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => widget.backend.mergeRecordings(_rec, other), 'Enregistrements fusionnés.');
  }

  Future<void> _removePart(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('Retirer la partie ${index + 2} et supprimer son fichier ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => widget.backend.removeRecordingPart(_rec, index), 'Partie retirée.');
  }

  /// Pose un repère au moment écouté.
  Future<void> _addMarker() async {
    final seconds = _player.currentState?.position.inSeconds ?? 0;
    final songs = await markerSuggestions(eventId: _rec.eventId);
    if (!mounted) return;
    final label = await askMarkerLabel(context, seconds: seconds, pinned: songs.pinned, all: songs.all);
    if (label == null || !mounted) return;
    await _setMarkers([..._rec.markers, RecordingMarker(seconds: seconds, label: label)]);
  }

  Future<void> _setMarkers(List<RecordingMarker> markers) async {
    try {
      final r = await widget.backend.setRecordingMarkers(_rec, markers);
      _changed = true;
      if (mounted) setState(() => _rec = r);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Repère non enregistré : ${explain(e)}')));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.backend.updateRecording(_rec.id, title: _title.text, notes: _notes.text);
      _changed = true;
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Points abordés enregistrés.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : ${explain(e)}')));
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
    if (!await attempt(() => widget.backend.deleteRecording(_rec), what: 'Suppression impossible')) return;
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final r = _rec;
    final parts = r.parts;
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
                    child: FutureBuilder<List<String>>(
                      future: _urls,
                      builder: (context, snap) => snap.hasError
                          ? ListTile(leading: const Icon(Icons.error_outline), title: Text('Lecture impossible : ${explain(snap.error!)}'))
                          : !snap.hasData
                              ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                              : AudioPlayerBar.parts(
                                  key: _player,
                                  urls: snap.data!,
                                  partDurations: [
                                    for (final p in parts) p.seconds == null ? null : Duration(seconds: p.seconds!),
                                  ],
                                  duration: r.durationSeconds == null ? null : Duration(seconds: r.durationSeconds!),
                                ),
                    ),
                  ),
                ),
                if (parts.length > 1)
                  for (final (i, p) in parts.indexed)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 12),
                      leading: CircleAvatar(radius: 13, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                      title: Text('Partie ${i + 1}${i == 0 ? '' : ' · à la suite'}'),
                      subtitle: p.seconds == null ? null : Text(formatDuration(p.seconds)),
                      trailing: widget.canEdit && i > 0 && !_adding
                          ? IconButton(
                              tooltip: 'Retirer cette partie',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => _removePart(i - 1),
                            )
                          : null,
                    ),
                if (widget.canEdit) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      icon: _adding
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.playlist_add_rounded),
                      label: Text(_adding ? 'Envoi…' : 'Ajouter la suite'),
                      onPressed: _adding ? null : _addNext,
                    ),
                  ),
                ],
                if (r.markers.isNotEmpty || widget.canEdit) ...[
                  const SectionHeader('Repères'),
                  if (r.markers.isEmpty)
                    Text('Écoute, puis pose un repère au début de chaque chant pour y revenir en un toucher.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  MarkerList(
                    markers: r.markers,
                    onTap: (m) => _player.currentState?.playFrom(Duration(seconds: m.seconds)),
                    onRemove: widget.canEdit ? (m) => _setMarkers([...r.markers]..remove(m)) : null,
                  ),
                  if (widget.canEdit)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Poser un repère ici'),
                        onPressed: _addMarker,
                      ),
                    ),
                ],
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
