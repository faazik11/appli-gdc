import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models.dart';
import '../platform/video_files.dart';
import '../services/agenda.dart';
import '../services/errors.dart';
import '../services/videos.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'recordings_screen.dart' show formatDuration;

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Prestations passées (ou du jour), la plus récente d'abord, pour y rattacher une vidéo.
Future<List<ChoirEvent>> _pastPrestations(AgendaBackend agenda) async {
  try {
    final soon = DateTime.now().add(const Duration(days: 1));
    final list = (await agenda.events()).where((e) => !e.isRehearsal && e.startsAt.isBefore(soon)).toList()
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    return list;
  } catch (_) {
    return const [];
  }
}

/// Onglet « Vidéos des prestations » : toutes les vidéos, de la plus récente à la plus ancienne.
class VideosScreen extends StatefulWidget {
  final AgendaBackend agenda;
  final bool canEdit;

  const VideosScreen({super.key, required this.agenda, required this.canEdit});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  List<Video>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await Videos.list();
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

  Future<void> _add() async {
    final file = await pickVideo();
    if (file == null || !mounted) return;
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => VideoFormScreen(agenda: widget.agenda, file: file)),
    );
    forgetVideo(file);
    if (done == true) _load();
  }

  Future<void> _open(Video v) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => VideoScreen(video: v, agenda: widget.agenda, canEdit: widget.canEdit)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    return Scaffold(
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              heroTag: null,
              icon: const Icon(Icons.video_call_rounded),
              label: const Text('Ajouter une vidéo'),
              onPressed: _add,
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(top: 12, bottom: 100), children: [
          ContentWidth(
            maxWidth: 760,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (items == null)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Text('Chargement impossible.\n$_error', textAlign: TextAlign.center),
                  ),
                )
              else if (items.isEmpty)
                EmptyState(
                  icon: Icons.videocam_outlined,
                  title: 'Aucune vidéo',
                  message: widget.canEdit
                      ? 'Appuie sur « Ajouter une vidéo » pour mettre en ligne la vidéo d\'une prestation. '
                          'Tout le groupe pourra la regarder.'
                      : 'Les vidéos des prestations ajoutées par les référents apparaîtront ici.',
                )
              else
                for (final v in items)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _open(v),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.play_arrow_rounded, color: AppColors.goldLight, size: 34),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(v.title, style: theme.textTheme.titleMedium),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    DateFormat('d MMMM y', 'fr_FR').format(v.date),
                                    formatDuration(v.durationSeconds),
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                                if (v.notes != null) ...[
                                  const SizedBox(height: 6),
                                  Text(v.notes!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                                ],
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Envoi d'une nouvelle vidéo ([file]) ou modification de la fiche d'une vidéo ([video]).
class VideoFormScreen extends StatefulWidget {
  final AgendaBackend agenda;
  final PickedVideo? file;
  final Video? video;

  const VideoFormScreen({super.key, required this.agenda, this.file, this.video});

  @override
  State<VideoFormScreen> createState() => _VideoFormScreenState();
}

class _VideoFormScreenState extends State<VideoFormScreen> {
  late final _title = TextEditingController(text: widget.video?.title);
  late final _notes = TextEditingController(text: widget.video?.notes);
  late String? _eventId = widget.video?.eventId;
  late DateTime? _filmedOn = widget.video?.filmedOn;
  List<ChoirEvent> _prestations = const [];
  ({int used, int limit})? _space;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _pastPrestations(widget.agenda).then((p) {
      if (mounted) setState(() => _prestations = p);
    });
    if (widget.file != null) {
      Videos.space().then((s) {
        if (mounted) setState(() => _space = s);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _pickEvent(String? id) {
    setState(() {
      _eventId = id;
      final e = _prestations.where((e) => e.id == id).firstOrNull;
      if (e != null) {
        _filmedOn = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
        if (_title.text.trim().isEmpty) _title.text = e.displayTitle;
      }
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _filmedOn ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _filmedOn = d);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Donne un titre à la vidéo.')));
      return;
    }
    final file = widget.file;
    setState(() => _progress = 0);
    // L'écran reste allumé pendant l'envoi : verrouiller le téléphone l'interromprait.
    WakelockPlus.enable().catchError((_) {});
    try {
      if (file != null) {
        await Videos.add(
          file: file,
          title: title,
          eventId: _eventId,
          filmedOn: _filmedOn,
          notes: _notes.text,
          onProgress: (f) {
            if (mounted) setState(() => _progress = f);
          },
        );
      } else {
        await Videos.update(widget.video!, title: title, eventId: _eventId, filmedOn: _filmedOn, notes: _notes.text);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(file != null ? 'Vidéo en ligne pour tout le groupe.' : 'Vidéo modifiée.')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _progress = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Envoi impossible : ${explain(e)}')));
      }
    } finally {
      WakelockPlus.disable().catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = widget.file;
    final space = _space;
    final sending = _progress != null;
    final tooBig = file != null && space != null && space.used + file.size > space.limit;
    return PopScope(
      canPop: !sending,
      child: Scaffold(
        appBar: AppBar(title: Text(file != null ? 'Nouvelle vidéo' : 'Modifier la vidéo')),
        body: ListView(children: [
          ContentWidth(
            maxWidth: 640,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (file != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.movie_outlined),
                      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        formatBytes(file.size),
                        formatDuration(file.seconds),
                        if (space != null) 'place libre : ${formatBytes((space.limit - space.used).clamp(0, space.limit))}',
                      ].where((s) => s.isNotEmpty).join(' · ')),
                    ),
                  ),
                if (tooBig)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Cette vidéo ne rentre pas dans la place libre. Supprime d\'anciennes vidéos ou compresse-la avant de l\'envoyer.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: _eventId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Prestation'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Aucune')),
                    for (final e in _prestations)
                      DropdownMenuItem(
                        value: e.id,
                        child: Text('${e.displayTitle} · ${DateFormat('d MMM y', 'fr_FR').format(e.startsAt)}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: sending ? null : _pickEvent,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  enabled: !sending,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Titre', hintText: 'Mariage de Sarah et Karim'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(_filmedOn == null
                      ? 'Date de la prestation'
                      : _cap(DateFormat('EEEE d MMMM y', 'fr_FR').format(_filmedOn!))),
                  onPressed: sending ? null : _pickDate,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  enabled: !sending,
                  minLines: 2,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Remarques (facultatif)', alignLabelWithHint: true),
                ),
                const SizedBox(height: 20),
                if (sending) ...[
                  LinearProgressIndicator(value: _progress == 0 ? null : _progress),
                  const SizedBox(height: 8),
                  Text(
                    file != null
                        ? 'Envoi… ${(_progress! * 100).round()} %. Garde l\'appli ouverte et le téléphone allumé jusqu\'à la fin.'
                        : 'Enregistrement…',
                    style: theme.textTheme.bodyMedium,
                  ),
                ] else
                  FilledButton.icon(
                    icon: Icon(file != null ? Icons.cloud_upload_rounded : Icons.check_rounded),
                    label: Text(file != null ? 'Envoyer la vidéo' : 'Enregistrer'),
                    onPressed: tooBig ? null : _save,
                  ),
                if (file != null && !sending) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Astuce : une minute de vidéo en 1080p pèse environ 100 à 200 Mo. '
                    'Filmer en 720p (Réglages › Appareil photo › Vidéo) divise la taille par deux ou trois.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Lecture d'une vidéo de prestation.
class VideoScreen extends StatefulWidget {
  final Video video;
  final AgendaBackend agenda;
  final bool canEdit;

  const VideoScreen({super.key, required this.video, required this.agenda, required this.canEdit});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final Future<Widget> _player = Videos.url(widget.video).then(videoPlayer);

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => VideoFormScreen(agenda: widget.agenda, video: widget.video)),
    );
    if (changed == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Supprimer cette vidéo pour tout le groupe ? Le fichier sera effacé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    if (!await attempt(() => Videos.delete(widget.video), what: 'Suppression impossible')) return;
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Vidéo'), actions: [
        if (widget.canEdit) ...[
          IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_outlined), onPressed: _edit),
          IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
        ],
      ]),
      body: ListView(children: [
        ContentWidth(
          maxWidth: 900,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: FutureBuilder<Widget>(
                  future: _player,
                  builder: (context, snap) => snap.hasError
                      ? Center(
                          child: Text('Lecture impossible : ${explain(snap.error!)}',
                              style: const TextStyle(color: Colors.white), textAlign: TextAlign.center))
                      : snap.data ?? const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  [
                    _cap(DateFormat('EEEE d MMMM y', 'fr_FR').format(v.date)),
                    formatDuration(v.durationSeconds),
                    if (v.sizeBytes != null) formatBytes(v.sizeBytes!),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (v.notes != null) ...[
                  const SizedBox(height: 16),
                  Text(v.notes!, style: theme.textTheme.bodyLarge),
                ],
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
