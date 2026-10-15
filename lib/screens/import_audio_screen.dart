import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

import '../models.dart';
import '../platform/pick_file.dart';
import '../services/agenda.dart';
import '../services/errors.dart';
import '../services/file_store.dart';
import '../services/workshop.dart';
import '../widgets/ui.dart';
import 'recordings_screen.dart';

/// Taille maximale d'un fichier dans le stockage (offre gratuite).
const _maxBytes = 50 * 1024 * 1024;

/// Fichier audio choisi sur le téléphone ou l'ordinateur (Dictaphone, enregistreur…).
class PickedAudio {
  final String name;
  final Uint8List bytes;
  final String type;
  final int? seconds;

  const PickedAudio({required this.name, required this.bytes, required this.type, this.seconds});

  String get extension => audioExtensionOf(type);
}

/// Durée d'un fichier audio, lue par le lecteur ; null si le téléphone ne la donne pas.
Future<int?> audioSeconds(Uint8List bytes, String type) async {
  final url = await localUrl(bytes, type);
  if (url == null) return null;
  final player = AudioPlayer();
  try {
    final d = await player.setUrl(url, preload: true).timeout(const Duration(seconds: 20));
    return d == null || d == Duration.zero ? null : d.inSeconds.clamp(1, 1 << 30);
  } catch (_) {
    return null;
  } finally {
    player.dispose().ignore();
  }
}

/// Ouvre le sélecteur de fichiers et vérifie le fichier ; null (avec un message) s'il ne convient pas.
Future<PickedAudio?> pickAudio(BuildContext context) async {
  void say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  // Sans filtre : sur iPhone, « audio/* » grise les fichiers récents de Dictaphone (.qta).
  final f = await pickOneFile();
  if (f == null) return null;
  final dot = f.name.lastIndexOf('.');
  final ext = dot < 0 ? '' : f.name.substring(dot + 1).toLowerCase();
  if (!audioTypes.containsKey(ext)) {
    if (context.mounted) say('Format non reconnu. Choisis un fichier audio (m4a, qta, mp3, wav, aac, ogg, webm ou flac).');
    return null;
  }
  final size = await f.length() ?? 0;
  if (size > _maxBytes) {
    if (context.mounted) {
      say('Fichier trop lourd (${(size / 1048576).round()} Mo, 50 Mo au maximum). '
          'Dans Dictaphone, choisis la qualité « Compressée » dans les réglages.');
    }
    return null;
  }
  final bytes = await f.readAsBytes();
  final type = audioTypes[ext]!;
  return PickedAudio(name: f.name, bytes: bytes, type: type, seconds: await audioSeconds(bytes, type));
}

String _stamp(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Dépose le fichier et l'ajoute à la suite de l'enregistrement [r].
Future<Recording> appendAudio(WorkBackend backend, Recording r, PickedAudio a) async {
  final path = await backend.upload(
      WorkBackend.recordingsBucket, 'repetition_${_stamp(r.recordedAt)}_suite.${a.extension}', a.bytes, a.type);
  final updated = await backend.appendRecordingPart(r, RecordingPart(path: path, seconds: a.seconds));
  await FileStore.instance.keep(WorkBackend.recordingsBucket, path, a.bytes);
  return updated;
}

/// Import d'un audio enregistré hors de l'appli : nouvel enregistrement, ou suite d'un enregistrement existant.
class ImportAudioScreen extends StatefulWidget {
  final WorkBackend backend;
  final AgendaBackend agenda;
  final PickedAudio audio;
  final List<Recording> recordings;

  const ImportAudioScreen({
    super.key,
    required this.backend,
    required this.agenda,
    required this.audio,
    required this.recordings,
  });

  @override
  State<ImportAudioScreen> createState() => _ImportAudioScreenState();
}

class _ImportAudioScreenState extends State<ImportAudioScreen> {
  late DateTime _day = DateUtils.dateOnly(DateTime.now());
  late TimeOfDay _time = TimeOfDay.fromDateTime(
      DateTime.now().subtract(Duration(seconds: widget.audio.seconds ?? 0)));
  final _title = TextEditingController();
  final _notes = TextEditingController();

  /// null : nouvel enregistrement ; sinon l'enregistrement à compléter.
  Recording? _after;
  bool _saving = false;

  /// Enregistrements récents proposés pour « à la suite de » (le plus récent d'abord).
  List<Recording> get _recent => widget.recordings
      .where((r) => DateTime.now().difference(r.recordedAt).inDays < 14)
      .take(6)
      .toList();

  DateTime get _when => DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);

  Future<String?> _eventOfDay() async {
    try {
      final events = await widget.agenda.events();
      final same = events.where((e) =>
          e.startsAt.year == _day.year && e.startsAt.month == _day.month && e.startsAt.day == _day.day);
      return (same.where((e) => e.isRehearsal).firstOrNull ?? same.firstOrNull)?.id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final a = widget.audio;
    try {
      if (_after != null) {
        await appendAudio(widget.backend, _after!, a);
      } else {
        // Gardé sur le téléphone d'abord, comme un enregistrement fait dans l'appli.
        final p = await PendingRecordings.keep(
          a.bytes,
          PendingRecording(
            key: 'import-${DateTime.now().millisecondsSinceEpoch}',
            recordedAt: _when,
            eventId: await _eventOfDay(),
            title: _title.text.trim().isEmpty ? null : _title.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            mimeType: a.type,
            durationSeconds: a.seconds ?? 0,
          ),
        );
        try {
          await PendingRecordings.send(widget.backend, p);
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Pas de connexion : l\'audio est gardé sur ce téléphone. Envoie-le depuis la page Répétitions.')));
          Navigator.pop(context, true);
          return;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_after != null
              ? 'Audio ajouté à la suite de « ${recordingTitle(_after!.recordedAt, _after!.title)} ».'
              : 'Audio importé et disponible pour tout le groupe.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import impossible : ${explain(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.audio;
    final recent = _recent;
    return Scaffold(
      appBar: AppBar(title: const Text('Importer un audio')),
      body: ListView(children: [
        ContentWidth(
          maxWidth: 640,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.audio_file_outlined),
                  title: Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    if (a.seconds != null) formatDuration(a.seconds),
                    '${(a.bytes.length / 1048576).toStringAsFixed(1)} Mo',
                  ].join(' · ')),
                ),
              ),
              const SectionHeader('Où le mettre ?'),
              RadioGroup<Recording?>(
                groupValue: _after,
                onChanged: (v) => setState(() => _after = v),
                child: Column(children: [
                  const RadioListTile<Recording?>(
                    value: null,
                    title: Text('Nouvel enregistrement'),
                    subtitle: Text('Une répétition enregistrée sans passer par l\'appli'),
                  ),
                  for (final r in recent)
                    RadioListTile<Recording?>(
                      value: r,
                      title: Text('À la suite de « ${recordingTitle(r.recordedAt, r.title)} »'),
                      subtitle: Text(
                          '${DateFormat('EEEE d MMMM \'à\' HH:mm', 'fr_FR').format(r.recordedAt)}'
                          '${r.durationSeconds == null ? '' : ' · ${formatDuration(r.durationSeconds)}'}'),
                    ),
                ]),
              ),
              if (_after != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'Les deux seront lus l\'un après l\'autre, comme un seul enregistrement.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else ...[
                const SectionHeader('Répétition'),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_rounded),
                      label: Text(DateFormat('EEE d MMM', 'fr_FR').format(_day)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _day,
                          firstDate: DateTime.now().subtract(const Duration(days: 730)),
                          lastDate: DateTime.now(),
                        );
                        if (d != null) setState(() => _day = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule_rounded),
                      label: Text(_time.format(context)),
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: _time);
                        if (t != null) setState(() => _time = t);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  decoration: InputDecoration(labelText: 'Titre', hintText: recordingTitle(_when, null)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: 12,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Points abordés',
                    hintText: 'Chants répétés : Vers la ville de Médine, Un seul regard',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_rounded),
                label: Text(_saving ? 'Envoi…' : (_after != null ? 'Ajouter à la suite' : 'Importer')),
                onPressed: _saving ? null : _save,
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
