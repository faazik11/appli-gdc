import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../services/agenda.dart';
import '../services/repository.dart';
import '../theme.dart';
import '../widgets/announcements.dart';
import '../widgets/install_card.dart';
import '../widgets/library_links.dart';
import '../widgets/ui.dart';
import 'agenda_screen.dart';
import 'booklet_editor_screen.dart';
import 'concert_screen.dart';
import 'members_screen.dart';
import 'pdf_view_screen.dart';
import 'song_form_screen.dart';
import 'song_screen.dart';
import 'tools_screen.dart';

class LibraryData {
  final List<Category> categories;
  final List<Song> songs;
  final List<Booklet> booklets;

  const LibraryData(this.categories, this.songs, this.booklets);
}

typedef LibraryLoader = Future<LibraryData> Function();

Future<LibraryData> _loadFromSupabase() async {
  final repo = Repository.instance;
  final r = await Future.wait([repo.categories(), repo.songs(), repo.booklets()]);
  return LibraryData(r[0] as List<Category>, r[1] as List<Song>, r[2] as List<Booklet>);
}

enum _Tab { home, songs, agenda, booklets, members }

class HomeScreen extends StatefulWidget {
  final Profile profile;
  final LibraryLoader load;
  final MembersPanel? membersPanel;
  final AgendaBackend? agenda;
  final int initialTab;

  /// Pour la démo : liens vers des fichiers locaux au lieu des liens signés.
  final Future<String> Function(String bucket, String path)? signUrl;

  const HomeScreen({
    super.key,
    required this.profile,
    this.load = _loadFromSupabase,
    this.membersPanel,
    this.agenda,
    this.initialTab = 0,
    this.signUrl,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = Repository.instance;
  late final AgendaBackend _agenda = widget.agenda ?? SupabaseAgenda();
  LibraryData _data = const LibraryData([], [], []);
  bool _loading = true;
  String? _error;
  _Tab _tab = _Tab.home;
  int? _categoryFilter;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = _tabs[widget.initialTab.clamp(0, _tabs.length - 1)];
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les chants : $e';
      });
    }
  }

  bool get _canEdit => widget.profile.isEditor;
  List<Category> get _songCategories => _data.categories.where((c) => !c.isBooklets).toList();
  Category? _categoryOf(Song s) => _data.categories.where((c) => c.id == s.categoryId).firstOrNull;
  List<_Tab> get _tabs => [_Tab.home, _Tab.songs, _Tab.agenda, _Tab.booklets, if (widget.profile.isAdmin) _Tab.members];

  // ---------- Navigation vers les autres écrans ----------

  Future<void> _openSong(Song song) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SongScreen(
        song: song,
        category: _categoryOf(song),
        canEdit: _canEdit,
        onEdit: () => _openSongForm(song: song),
      ),
    ));
  }

  Future<void> _openSongForm({Song? song, int? categoryId}) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => SongFormScreen(categories: _songCategories, song: song, initialCategoryId: categoryId),
    ));
    if (saved == true) _load();
  }

  Future<void> _openBookletEditor({Booklet? booklet}) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BookletEditorScreen(categories: _songCategories, songs: _data.songs, booklet: booklet),
    ));
    if (saved == true) _load();
  }

  void _openTools(int tab) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ToolsScreen(initialTab: tab)));

  void _openConcert(Booklet b) {
    if (b.pdfPath == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConcertScreen(title: b.title, bucket: Repository.bookletsBucket, path: b.pdfPath!, signUrl: widget.signUrl),
    ));
  }

  LibraryLinks get _links => LibraryLinks(
        songs: _data.songs,
        categories: _data.categories,
        booklets: _data.booklets,
        openSong: _openSong,
        openBooklet: _openBooklet,
        openConcert: _openConcert,
      );

  void _openBooklet(Booklet b) {
    if (b.pdfPath == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfViewScreen(title: b.title, bucket: Repository.bookletsBucket, path: b.pdfPath!),
    ));
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

  void _newBookletSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: CategoryIcon(CategoryStyle.of('Livrets'), size: 40),
              title: const Text('Créer un livret'),
              subtitle: const Text('Choisis les chants, les parties, et le PDF se fait tout seul'),
              onTap: () {
                Navigator.pop(sheet);
                _openBookletEditor();
              },
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.upload_file_rounded)),
              title: const Text('Importer un livret PDF'),
              subtitle: const Text('Un livret que tu as déjà'),
              onTap: () {
                Navigator.pop(sheet);
                _importBooklet();
              },
            ),
          ]),
        ),
      ),
    );
  }

  void _showCategory(int? categoryId) => setState(() {
        _categoryFilter = categoryId;
        _tab = _Tab.songs;
      });

  // ---------- Mise en page ----------

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Connexion impossible',
                message: _error!,
                action: FilledButton(onPressed: _load, child: const Text('Réessayer')),
              )
            : switch (_tab) {
                _Tab.home => _homeTab(wide),
                _Tab.songs => _songsTab(),
                _Tab.agenda => AgendaPanel(profile: widget.profile, backend: _agenda, links: _links),
                _Tab.booklets => _bookletsTab(wide),
                _Tab.members => widget.membersPanel ?? const MembersPanel(),
              };

    final destinations = [
      for (final t in _tabs)
        switch (t) {
          _Tab.home => (Icons.home_outlined, Icons.home_rounded, 'Accueil'),
          _Tab.songs => (Icons.library_music_outlined, Icons.library_music_rounded, 'Chants'),
          _Tab.agenda => (Icons.event_outlined, Icons.event_rounded, 'Agenda'),
          _Tab.booklets => (Icons.menu_book_outlined, Icons.menu_book_rounded, 'Livrets'),
          _Tab.members => (Icons.groups_outlined, Icons.groups_rounded, 'Membres'),
        },
    ];
    final index = _tabs.indexOf(_tab);
    void select(int i) => setState(() {
          _tab = _tabs[i];
          if (_tab == _Tab.songs && i != index) _categoryFilter = null;
        });

    final fab = _fab();
    if (wide) {
      return Scaffold(
        floatingActionButton: fab,
        body: Row(children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1200,
            selectedIndex: index,
            onDestinationSelected: select,
            leading: const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: AppLogo(size: 48)),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: SafeArea(child: body)),
        ]),
      );
    }
    return Scaffold(
      floatingActionButton: fab,
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: select,
        destinations: [
          for (final d in destinations)
            NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }

  Widget? _fab() {
    if (!_canEdit || _loading) return null;
    return switch (_tab) {
      _Tab.songs => FloatingActionButton.extended(
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nouveau chant'),
          onPressed: () => _openSongForm(categoryId: _categoryFilter),
        ),
      _Tab.booklets => FloatingActionButton.extended(
          icon: const Icon(Icons.auto_stories_rounded),
          label: const Text('Nouveau livret'),
          onPressed: _newBookletSheet,
        ),
      _ => null,
    };
  }

  // ---------- Accueil ----------

  Widget _homeTab(bool wide) {
    final songsByCategory = <int, int>{};
    for (final s in _data.songs) {
      songsByCategory[s.categoryId] = (songsByCategory[s.categoryId] ?? 0) + 1;
    }
    final recent = [..._data.songs]
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100 ? 5 : (width >= 700 ? 4 : 2);
    Widget categoryCard(Category c) {
      final n = c.isBooklets ? _data.booklets.length : (songsByCategory[c.id] ?? 0);
      return CategoryCard(
        name: c.name,
        count: n,
        countLabel: c.isBooklets ? (n > 1 ? 'livrets' : 'livret') : (n > 1 ? 'chants' : 'chant'),
        onTap: () => c.isBooklets ? setState(() => _tab = _Tab.booklets) : _showCategory(c.id),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        _hero(),
        ContentWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const InstallCard(),
            AnnouncementsSection(profile: widget.profile, backend: _agenda),
            NextEventsSection(
              profile: widget.profile,
              backend: _agenda,
              onOpenAgenda: () => setState(() => _tab = _Tab.agenda),
              links: _links,
            ),
            const SectionHeader('Bibliothèque'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.15,
                  ),
                  children: [
                    for (final c in columns == 5 ? _data.categories : _songCategories) categoryCard(c),
                  ],
                ),
                // Sur téléphone et tablette, la carte Livrets occupe toute la largeur.
                if (columns != 5)
                  for (final c in _data.categories.where((c) => c.isBooklets))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(height: 110, width: double.infinity, child: categoryCard(c)),
                    ),
              ]),
            ),
            const SectionHeader('Outils'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(child: _quickAction(Icons.tune_rounded, 'Diapason', () => _openTools(0))),
                const SizedBox(width: 12),
                Expanded(child: _quickAction(Icons.timer_outlined, 'Métronome', () => _openTools(1))),
              ]),
            ),
            if (_canEdit) ...[
              const SectionHeader('Actions rapides'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(spacing: 12, runSpacing: 12, children: [
                  _quickAction(Icons.library_add_rounded, 'Ajouter un chant', () => _openSongForm()),
                  _quickAction(Icons.auto_stories_rounded, 'Créer un livret', () => _openBookletEditor()),
                  _quickAction(Icons.upload_file_rounded, 'Importer un livret', _importBooklet),
                ]),
              ),
            ],
            SectionHeader(
              'Ajoutés récemment',
              actionLabel: _data.songs.isEmpty ? null : 'Tout voir',
              onAction: () => _showCategory(null),
            ),
            if (recent.isEmpty)
              EmptyState(
                icon: Icons.queue_music_rounded,
                title: 'Aucun chant pour l\'instant',
                message: _canEdit
                    ? 'Ajoute ton premier chant avec ses paroles, sa vidéo YouTube ou son audio.'
                    : 'Les chants ajoutés par le chef de chœur apparaîtront ici.',
                action: _canEdit
                    ? FilledButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Ajouter un chant'),
                        onPressed: () => _openSongForm())
                    : null,
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(children: [
                  for (final s in recent.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SongCard(song: s, category: _categoryOf(s), onTap: () => _openSong(s)),
                    ),
                ]),
              ),
            if (_data.booklets.isNotEmpty) ...[
              SectionHeader('Derniers livrets',
                  actionLabel: 'Tout voir', onAction: () => setState(() => _tab = _Tab.booklets)),
              SizedBox(
                height: 170,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: _data.booklets.length.clamp(0, 8),
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => SizedBox(
                    width: 230,
                    child: BookletCard(booklet: _data.booklets[i], onTap: () => _openBooklet(_data.booklets[i])),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _hero() {
    final firstName = widget.profile.fullName.trim().split(' ').first;
    final today = DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now());
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Stack(children: [
        Positioned(
          right: -30,
          top: -20,
          child: Icon(Icons.music_note_rounded, size: 200, color: Colors.white.withValues(alpha: 0.06)),
        ),
        Positioned(
          right: 90,
          bottom: -30,
          child: Icon(Icons.queue_music_rounded, size: 120, color: AppColors.gold.withValues(alpha: 0.12)),
        ),
        ContentWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 14, 26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const AppLogo(size: 40),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Groupe de Chant Narbonne',
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16, letterSpacing: 0.5)),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Mon compte',
                  onSelected: (v) {
                    if (v == 'logout') Supabase.instance.client.auth.signOut();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(enabled: false, child: Text('${widget.profile.fullName} · ${roleLabel(widget.profile.role)}')),
                    const PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
                  ],
                  child: Avatar(widget.profile.fullName, radius: 20),
                ),
              ]),
              const SizedBox(height: 26),
              Text(_capitalize(today),
                  style: TextStyle(fontFamily: 'Poppins', color: AppColors.goldLight.withValues(alpha: 0.95), fontSize: 13, letterSpacing: 0.4)),
              const SizedBox(height: 4),
              Text(firstName.isEmpty ? 'Bonjour !' : 'Bonjour $firstName',
                  style: const TextStyle(fontFamily: 'DMSerifDisplay', color: Colors.white, fontSize: 34, height: 1.1)),
              const SizedBox(height: 6),
              Text('Prêt pour la répétition ?',
                  style: TextStyle(fontFamily: 'Poppins', color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
              const SizedBox(height: 20),
              _searchLauncher(),
              const SizedBox(height: 18),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _stat('${_data.songs.length}', 'chants'),
                _stat('${_data.booklets.length}', 'livrets'),
                _stat('${_data.songs.where((s) => s.hasYoutube || s.hasAudio).length}', 'à écouter'),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _searchLauncher() => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showCategory(null),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(Icons.search_rounded, color: AppColors.aubergine),
              SizedBox(width: 10),
              Text('Rechercher un chant…', style: TextStyle(fontFamily: 'Poppins', color: Color(0xFF6E6578))),
            ]),
          ),
        ),
      );

  Widget _stat(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: RichText(
          text: TextSpan(children: [
            TextSpan(
                text: '$value ',
                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.goldLight, fontWeight: FontWeight.w700, fontSize: 15)),
            TextSpan(text: label, style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 13)),
          ]),
        ),
      );

  Widget _quickAction(IconData icon, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: theme.colorScheme.tertiary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------- Chants ----------

  Widget _songsTab() {
    final theme = Theme.of(context);
    final songs = _data.songs
        .where((s) => _categoryFilter == null || s.categoryId == _categoryFilter)
        .where((s) =>
            _query.isEmpty ||
            s.title.toLowerCase().contains(_query) ||
            s.tags.any((t) => t.toLowerCase().contains(_query)))
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
        ContentWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Chants', style: theme.textTheme.headlineLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text('${_data.songs.length} chants dans la bibliothèque',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Titre ou mot-clé',
                ),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            SizedBox(
              height: 60,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                scrollDirection: Axis.horizontal,
                children: [
                  _filterChip(null, 'Tous'),
                  for (final c in _songCategories) _filterChip(c.id, c.name),
                ],
              ),
            ),
            if (songs.isEmpty)
              EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Aucun chant trouvé',
                message: _query.isEmpty ? 'Cette catégorie est encore vide.' : 'Essaie un autre mot.',
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(children: [
                  for (final s in songs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SongCard(song: s, category: _categoryOf(s), onTap: () => _openSong(s)),
                    ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _filterChip(int? id, String label) {
    final selected = _categoryFilter == id;
    final style = CategoryStyle.of(label);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: id == null ? null : Icon(style.icon, size: 18, color: selected ? Colors.white : style.colors.first),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: id == null ? AppColors.aubergine : style.colors.first,
        labelStyle: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w500,
          color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
        ),
        onSelected: (_) => setState(() => _categoryFilter = id),
      ),
    );
  }

  // ---------- Livrets ----------

  Widget _bookletsTab(bool wide) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100 ? 4 : (width >= 700 ? 3 : (width >= 420 ? 2 : 1));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
        ContentWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Livrets', style: theme.textTheme.headlineLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text('Les programmes de vos prestations',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            if (_data.booklets.isEmpty)
              EmptyState(
                icon: Icons.auto_stories_rounded,
                title: 'Aucun livret',
                message: _canEdit
                    ? 'Crée un livret en choisissant les chants : sommaire et parties sont générés automatiquement.'
                    : 'Les livrets des prochaines prestations apparaîtront ici.',
                action: _canEdit
                    ? FilledButton.icon(
                        icon: const Icon(Icons.auto_stories_rounded),
                        label: const Text('Créer un livret'),
                        onPressed: () => _openBookletEditor())
                    : null,
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    mainAxisExtent: 158,
                  ),
                  children: [
                    for (final b in _data.booklets)
                      BookletCard(
                        booklet: b,
                        onTap: () => _openBooklet(b),
                        menu: _canEdit ? _bookletMenu(b) : null,
                      ),
                  ],
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _bookletMenu(Booklet b) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
        onSelected: (action) async {
          if (action == 'edit') _openBookletEditor(booklet: b);
          if (action == 'delete' && await _confirm(context, 'Supprimer « ${b.title} » ?')) {
            await _repo.deleteBooklet(b);
            _load();
          }
        },
        itemBuilder: (_) => [
          if (b.parts.isNotEmpty) const PopupMenuItem(value: 'edit', child: Text('Modifier')),
          const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
        ],
      );
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

Future<String?> _askText(BuildContext context, String label, {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(label),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('OK')),
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
