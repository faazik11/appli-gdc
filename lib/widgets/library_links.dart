import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'ui.dart';

/// Accès à la bibliothèque depuis l'agenda : chants et livrets, et comment les ouvrir.
class LibraryLinks {
  final List<Song> songs;
  final List<Category> categories;
  final List<Booklet> booklets;
  final void Function(Song song) openSong;
  final void Function(Booklet booklet) openBooklet;
  final void Function(Booklet booklet) openConcert;

  const LibraryLinks({
    this.songs = const [],
    this.categories = const [],
    this.booklets = const [],
    required this.openSong,
    required this.openBooklet,
    required this.openConcert,
  });

  static final empty = LibraryLinks(openSong: (_) {}, openBooklet: (_) {}, openConcert: (_) {});

  Song? song(String id) => songs.where((s) => s.id == id).firstOrNull;
  Booklet? booklet(String? id) => id == null ? null : booklets.where((b) => b.id == id).firstOrNull;
  Category? categoryOf(Song s) => categories.where((c) => c.id == s.categoryId).firstOrNull;

  /// Chants d'un événement : ceux choisis, sinon ceux du livret lié.
  List<Song> songsOf(ChoirEvent e) {
    final ids = e.songIds.isNotEmpty
        ? e.songIds
        : [for (final p in booklet(e.bookletId)?.parts ?? const <BookletPart>[]) ...p.songIds];
    return ids.map(song).whereType<Song>().toList();
  }
}

/// Choix de plusieurs chants, dans l'ordre où on les coche.
Future<List<String>?> pickSongs(BuildContext context, LibraryLinks links, List<String> initial) {
  return Navigator.of(context).push<List<String>>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _SongPicker(links: links, initial: initial),
  ));
}

class _SongPicker extends StatefulWidget {
  final LibraryLinks links;
  final List<String> initial;

  const _SongPicker({required this.links, required this.initial});

  @override
  State<_SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends State<_SongPicker> {
  late final List<String> _selected = [...widget.initial];
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final songs = widget.links.songs
        .where((s) => _query.isEmpty || s.title.toLowerCase().contains(_query))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty ? 'Choisir des chants' : '${_selected.length} chant(s) choisi(s)'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: () => Navigator.pop(context, _selected), child: const Text('Valider')),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Rechercher un chant'),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: songs.isEmpty
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'Aucun chant', message: 'Ajoute d\'abord des chants à la bibliothèque.')
              : ListView(children: [
                  for (final s in songs)
                    CheckboxListTile(
                      value: _selected.contains(s.id),
                      secondary: CategoryIcon(CategoryStyle.of(widget.links.categoryOf(s)?.name ?? ''), size: 36),
                      title: Text(s.title),
                      subtitle: Text(widget.links.categoryOf(s)?.name ?? ''),
                      onChanged: (v) => setState(() => v == true ? _selected.add(s.id) : _selected.remove(s.id)),
                    ),
                ]),
        ),
      ]),
    );
  }
}
