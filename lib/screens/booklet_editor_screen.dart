import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/booklet_builder.dart';
import '../services/repository.dart';
import 'pdf_view_screen.dart';

/// Création d'un livret : choix des chants, découpage en parties, génération du PDF.
class BookletEditorScreen extends StatefulWidget {
  final List<Category> categories;
  final List<Song> songs;
  final Booklet? booklet;

  const BookletEditorScreen({super.key, required this.categories, required this.songs, this.booklet});

  @override
  State<BookletEditorScreen> createState() => _BookletEditorScreenState();
}

class _BookletEditorScreenState extends State<BookletEditorScreen> {
  final _repo = Repository.instance;
  late final _title = TextEditingController(text: widget.booklet?.title);
  late DateTime? _date = widget.booklet?.eventDate;
  late final List<BookletPart> _parts = widget.booklet?.parts
          .map((p) => BookletPart(name: p.name, songIds: [...p.songIds]))
          .toList() ??
      [BookletPart(name: '')];
  late final Map<String, Song> _songsById = {for (final s in widget.songs) s.id: s};
  String? _progress;

  int get _songCount => _parts.fold(0, (n, p) => n + p.songIds.length);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _addSongs(BookletPart part) async {
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (_) => _SongPickerDialog(
        categories: widget.categories,
        songs: widget.songs,
        alreadyIn: part.songIds.toSet(),
      ),
    );
    if (picked != null) setState(() => part.songIds.addAll(picked));
  }

  Future<void> _generate() async {
    final title = _title.text.trim();
    if (title.isEmpty || _songCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Donne un titre au livret et ajoute au moins un chant.')));
      return;
    }
    setState(() => _progress = 'Préparation…');
    try {
      final bytes = await BookletBuilder((path) => _repo.download(Repository.lyricsBucket, path)).build(
        title: title,
        eventDate: _date,
        parts: _parts,
        songsById: _songsById,
        onProgress: (step) => setState(() => _progress = 'Ajout de « $step »'),
      );
      setState(() => _progress = 'Enregistrement…');
      final path = await _repo.upload(
          Repository.bookletsBucket, '$title.pdf', Uint8List.fromList(bytes), 'application/pdf');
      final old = widget.booklet;
      await _repo.saveBooklet(id: old?.id, title: title, eventDate: _date, parts: _parts, pdfPath: path);
      if (old?.pdfPath != null) {
        await _repo.deleteFiles(Repository.bookletsBucket, [old!.pdfPath!]);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PdfViewScreen(title: title, bucket: Repository.bookletsBucket, path: path),
        ),
        result: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _progress = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Génération impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.booklet == null ? 'Nouveau livret' : 'Modifier le livret')),
      body: busy
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_progress!),
              ]),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Titre du livret', hintText: 'Mariage de…'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(_date == null
                      ? 'Date de la prestation (facultatif)'
                      : DateFormat.yMMMMd('fr_FR').format(_date!)),
                  onTap: _pickDate,
                  trailing: _date == null
                      ? null
                      : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _date = null)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Les parties apparaissent dans le sommaire avec une page de titre. '
                  'Laisse le nom vide pour mettre des chants sans partie.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _parts.length; i++) _partCard(i),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une partie'),
                  onPressed: () => setState(() => _parts.add(BookletPart(name: 'Partie ${_parts.length + 1}'))),
                ),
              ],
            ),
      floatingActionButton: busy
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.picture_as_pdf),
              label: Text('Générer le livret ($_songCount chants)'),
              onPressed: _generate,
            ),
    );
  }

  Widget _partCard(int index) {
    final part = _parts[index];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: part.name,
                  decoration: const InputDecoration(labelText: 'Nom de la partie', hintText: 'Entrée, Méditation…'),
                  onChanged: (v) => part.name = v,
                ),
              ),
              IconButton(
                tooltip: 'Monter',
                icon: const Icon(Icons.arrow_upward),
                onPressed: index == 0
                    ? null
                    : () => setState(() => _parts.insert(index - 1, _parts.removeAt(index))),
              ),
              IconButton(
                tooltip: 'Descendre',
                icon: const Icon(Icons.arrow_downward),
                onPressed: index == _parts.length - 1
                    ? null
                    : () => setState(() => _parts.insert(index + 1, _parts.removeAt(index))),
              ),
              IconButton(
                tooltip: 'Supprimer la partie',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => _parts.removeAt(index)),
              ),
            ]),
            ReorderableListView(
              key: ObjectKey(part),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) => setState(() {
                part.songIds.insert(to, part.songIds.removeAt(from));
              }),
              children: [
                for (var j = 0; j < part.songIds.length; j++)
                  ListTile(
                    key: ValueKey('${part.hashCode}-$j-${part.songIds[j]}'),
                    dense: true,
                    leading: ReorderableDragStartListener(index: j, child: const Icon(Icons.drag_handle)),
                    title: Text(_songsById[part.songIds[j]]?.title ?? 'Chant supprimé'),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(() => part.songIds.removeAt(j)),
                    ),
                  ),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.playlist_add),
              label: const Text('Ajouter des chants'),
              onPressed: () => _addSongs(part),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongPickerDialog extends StatefulWidget {
  final List<Category> categories;
  final List<Song> songs;
  final Set<String> alreadyIn;

  const _SongPickerDialog({required this.categories, required this.songs, required this.alreadyIn});

  @override
  State<_SongPickerDialog> createState() => _SongPickerDialogState();
}

class _SongPickerDialogState extends State<_SongPickerDialog> {
  final _selected = <String>[];
  int? _categoryId;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.songs
        .where((s) => _categoryId == null || s.categoryId == _categoryId)
        .where((s) => _query.isEmpty || s.title.toLowerCase().contains(_query))
        .toList();
    return AlertDialog(
      title: const Text('Choisir des chants'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 500,
        height: 500,
        child: Column(children: [
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher', isDense: true),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('Tous'),
                  selected: _categoryId == null,
                  onSelected: (_) => setState(() => _categoryId = null),
                ),
              ),
              for (final c in widget.categories)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: ListView(children: [
              for (final s in visible)
                CheckboxListTile(
                  value: _selected.contains(s.id),
                  title: Text(s.title),
                  subtitle: widget.alreadyIn.contains(s.id) ? const Text('Déjà dans cette partie') : null,
                  onChanged: (v) => setState(() => v! ? _selected.add(s.id) : _selected.remove(s.id)),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text('Ajouter (${_selected.length})'),
        ),
      ],
    );
  }
}
