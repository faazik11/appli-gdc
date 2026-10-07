import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../services/repository.dart';
import 'booklet_editor_screen.dart';
import 'members_screen.dart';
import 'pdf_view_screen.dart';
import 'song_form_screen.dart';
import 'song_screen.dart';

class HomeScreen extends StatefulWidget {
  final Profile profile;

  const HomeScreen({super.key, required this.profile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = Repository.instance;
  List<Category> _categories = [];
  List<Song> _songs = [];
  List<Booklet> _booklets = [];
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_repo.categories(), _repo.songs(), _repo.booklets()]);
      setState(() {
        _categories = results[0] as List<Category>;
        _songs = results[1] as List<Song>;
        _booklets = results[2] as List<Booklet>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les chants : $e';
      });
    }
  }

  List<Category> get _songCategories => _categories.where((c) => !c.isBooklets).toList();

  Future<void> _openSongForm({Song? song, int? categoryId}) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => SongFormScreen(
        categories: _songCategories,
        song: song,
        initialCategoryId: categoryId,
      ),
    ));
    if (saved == true) _load();
  }

  Future<void> _openBookletEditor({Booklet? booklet}) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BookletEditorScreen(
        categories: _songCategories,
        songs: _songs,
        booklet: booklet,
      ),
    ));
    if (saved == true) _load();
  }

  Future<void> _importBooklet() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (file == null || !mounted) return;
    final title = await _askText(context, 'Titre du livret', initial: file.name.replaceAll('.pdf', ''));
    if (title == null || title.isEmpty) return;
    final bytes = await file.readAsBytes();
    final path = await _repo.upload(Repository.bookletsBucket, file.name, bytes, 'application/pdf');
    await _repo.saveBooklet(title: title, parts: const [], pdfPath: path);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final canEdit = widget.profile.isEditor;
    return DefaultTabController(
      length: _categories.length,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Appli GDC'),
            actions: [
              if (widget.profile.isAdmin)
                IconButton(
                  tooltip: 'Membres',
                  icon: const Icon(Icons.group),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const MembersScreen())),
                ),
              IconButton(
                tooltip: 'Se déconnecter',
                icon: const Icon(Icons.logout),
                onPressed: () => Supabase.instance.client.auth.signOut(),
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final c in _categories) Tab(text: c.name)],
            ),
          ),
          body: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : TabBarView(
                  children: [
                    for (final c in _categories)
                      c.isBooklets ? _bookletList(canEdit) : _songList(c, canEdit),
                  ],
                ),
          floatingActionButton: canEdit ? _fab(context) : null,
        );
      }),
    );
  }

  Widget _fab(BuildContext context) {
    return FloatingActionButton.extended(
      icon: const Icon(Icons.add),
      label: const Text('Ajouter'),
      onPressed: () {
        final category = _categories[DefaultTabController.of(context).index];
        if (!category.isBooklets) {
          _openSongForm(categoryId: category.id);
          return;
        }
        showModalBottomSheet<void>(
          context: context,
          builder: (sheet) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.auto_stories),
                title: const Text('Créer un livret à partir des chants'),
                onTap: () {
                  Navigator.pop(sheet);
                  _openBookletEditor();
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Importer un livret PDF existant'),
                onTap: () {
                  Navigator.pop(sheet);
                  _importBooklet();
                },
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Rechercher un chant',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
      );

  Widget _songList(Category category, bool canEdit) {
    final songs = _songs
        .where((s) => s.categoryId == category.id)
        .where((s) =>
            _query.isEmpty ||
            s.title.toLowerCase().contains(_query) ||
            s.tags.any((t) => t.toLowerCase().contains(_query)))
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _searchField(),
          if (songs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Aucun chant pour l\'instant.')),
            ),
          for (final song in songs)
            ListTile(
              title: Text(song.title),
              subtitle: song.tags.isEmpty ? null : Text(song.tags.join(' · ')),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (song.lyricsPdfPath != null) const Icon(Icons.description_outlined, size: 20),
                if (song.youtubeUrl != null) const Icon(Icons.smart_display_outlined, size: 20),
                if (song.audioPath != null) const Icon(Icons.audiotrack, size: 20),
              ]),
              onTap: () async {
                final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
                  builder: (_) => SongScreen(
                    song: song,
                    canEdit: canEdit,
                    onEdit: () => _openSongForm(song: song),
                  ),
                ));
                if (changed == true) _load();
              },
            ),
        ],
      ),
    );
  }

  Widget _bookletList(bool canEdit) {
    final dateFormat = DateFormat.yMMMMd('fr_FR');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (_booklets.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Aucun livret pour l\'instant.')),
            ),
          for (final b in _booklets)
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: Text(b.title),
              subtitle: Text([
                if (b.eventDate != null) dateFormat.format(b.eventDate!),
                if (b.parts.isNotEmpty)
                  '${b.parts.fold<int>(0, (n, p) => n + p.songIds.length)} chants',
              ].join(' · ')),
              trailing: canEdit
                  ? PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'edit') _openBookletEditor(booklet: b);
                        if (action == 'delete' && await _confirm(context, 'Supprimer « ${b.title} » ?')) {
                          await _repo.deleteBooklet(b);
                          _load();
                        }
                      },
                      itemBuilder: (_) => [
                        if (b.parts.isNotEmpty)
                          const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                        const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                      ],
                    )
                  : null,
              onTap: b.pdfPath == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PdfViewScreen(
                          title: b.title,
                          bucket: Repository.bookletsBucket,
                          path: b.pdfPath!,
                        ),
                      )),
            ),
        ],
      ),
    );
  }
}

Future<String?> _askText(BuildContext context, String label, {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(label),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(BuildContext context, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
      ],
    ),
  );
  return ok ?? false;
}
