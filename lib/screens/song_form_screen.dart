import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models.dart';
import '../services/repository.dart';

/// Ajout ou modification d'un chant (réservé aux chefs de chœur et admins).
class SongFormScreen extends StatefulWidget {
  final List<Category> categories;
  final Song? song;
  final int? initialCategoryId;

  const SongFormScreen({super.key, required this.categories, this.song, this.initialCategoryId});

  @override
  State<SongFormScreen> createState() => _SongFormScreenState();
}

class _SongFormScreenState extends State<SongFormScreen> {
  final _repo = Repository.instance;
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.song?.title);
  late final _youtube = TextEditingController(text: widget.song?.youtubeUrl);
  late final _tags = TextEditingController(text: widget.song?.tags.join(', '));
  late final _notes = TextEditingController(text: widget.song?.notes);
  late int _categoryId =
      widget.song?.categoryId ?? widget.initialCategoryId ?? widget.categories.first.id;
  PlatformFile? _pdf;
  PlatformFile? _audio;
  late bool _keepPdf = widget.song?.lyricsPdfPath != null;
  late bool _keepAudio = widget.song?.audioPath != null;
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final old = widget.song;
      var pdfPath = _keepPdf ? old?.lyricsPdfPath : null;
      var audioPath = _keepAudio ? old?.audioPath : null;
      if (_pdf != null) {
        pdfPath = await _repo.upload(
            Repository.lyricsBucket, _pdf!.name, await _pdf!.readAsBytes(), 'application/pdf');
      }
      if (_audio != null) {
        audioPath = await _repo.upload(Repository.audioBucket, _audio!.name,
            await _audio!.readAsBytes(), audioContentType(_audio!.extension));
      }
      await _repo.saveSong(
        id: old?.id,
        title: _title.text.trim(),
        categoryId: _categoryId,
        youtubeUrl: _youtube.text,
        notes: _notes.text,
        tags: _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
        lyricsPdfPath: pdfPath,
        audioPath: audioPath,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('Supprimer « ${widget.song!.title} » ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteSong(widget.song!);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _fileRow({
    required IconData icon,
    required String label,
    required String? pickedName,
    required bool hasExisting,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final status = pickedName ?? (hasExisting ? 'Fichier enregistré' : 'Aucun fichier');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(status),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (pickedName != null || hasExisting)
          IconButton(tooltip: 'Retirer', icon: const Icon(Icons.close), onPressed: onClear),
        OutlinedButton(onPressed: onPick, child: const Text('Choisir')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.song == null ? 'Nouveau chant' : 'Modifier le chant'),
        actions: [
          if (widget.song != null)
            IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Titre'),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Titre obligatoire' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: [
                for (final c in widget.categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _youtube,
              decoration: const InputDecoration(
                labelText: 'Lien YouTube (facultatif)',
                hintText: 'https://www.youtube.com/watch?v=…',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                return YoutubePlayerController.convertUrlToId(v.trim()) == null
                    ? 'Lien YouTube non reconnu'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Mots-clés (séparés par des virgules)',
                hintText: 'Noël, entrée, a cappella',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes pour les choristes'),
            ),
            const SizedBox(height: 16),
            _fileRow(
              icon: Icons.description,
              label: 'Paroles (PDF)',
              pickedName: _pdf?.name,
              hasExisting: _keepPdf,
              onPick: () async {
                final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
                if (f != null) setState(() => _pdf = f);
              },
              onClear: () => setState(() {
                _pdf = null;
                _keepPdf = false;
              }),
            ),
            _fileRow(
              icon: Icons.audiotrack,
              label: 'Audio (MP3, M4A, WAV…)',
              pickedName: _audio?.name,
              hasExisting: _keepAudio,
              onPick: () async {
                final f = await FilePicker.pickFile(type: FileType.audio);
                if (f != null) setState(() => _audio = f);
              },
              onClear: () => setState(() {
                _audio = null;
                _keepAudio = false;
              }),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
