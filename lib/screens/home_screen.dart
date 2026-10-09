import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../services/agenda.dart';
import '../services/file_store.dart';
import '../services/offline.dart';
import '../services/page_images.dart';
import '../services/repository.dart';
import '../services/workshop.dart';
import '../theme.dart';
import '../widgets/announcements.dart';
import '../widgets/install_card.dart';
import '../widgets/library_links.dart';
import '../widgets/ui.dart';
import 'agenda_screen.dart';
import 'booklet_editor_screen.dart';
import 'concert_screen.dart';
import 'members_screen.dart';
import 'new_password_screen.dart';
import 'inventory_screen.dart';
import 'pdf_view_screen.dart';
import 'recordings_screen.dart';
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

enum _Tab { home, songs, agenda, recordings, booklets, inventory, members }

class HomeScreen extends StatefulWidget {
  final Profile profile;
  final LibraryLoader load;
  final MembersPanel? membersPanel;
  final AgendaBackend? agenda;
  final WorkBackend? work;
  final int initialTab;


  const HomeScreen({
    super.key,
    required this.profile,
    this.load = _loadFromSupabase,
    this.membersPanel,
    this.agenda,
    this.work,
    this.initialTab = 0,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = Repository.instance;
  late final AgendaBackend _agenda = widget.agenda ?? SupabaseAgenda();
  late final WorkBackend _work = widget.work ?? SupabaseWork();
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
  List<_Tab> get _tabs => [
        _Tab.home,
        _Tab.songs,
        _Tab.agenda,
        _Tab.recordings,
        _Tab.inventory,
        if (widget.profile.isAdmin) _Tab.members,
      ];

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
      builder: (_) => ConcertScreen(title: b.title, bucket: Repository.bookletsBucket, path: b.pdfPath!),
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

  /// Télécharge livrets, paroles et audios pour qu'ils s'ouvrent sans attendre, même hors connexion.
  Future<void> _downloadAll() async {
    final files = [
      for (final b in _data.booklets)
        if (b.pdfPath != null) (Repository.bookletsBucket, b.pdfPath!),
      for (final s in _data.songs)
        if (s.lyricsPdfPath != null) (Repository.lyricsBucket, s.lyricsPdfPath!),
      for (final s in _data.songs)
        if (s.audioPath != null) (Repository.audioBucket, s.audioPath!),
    ];
    // Les livrets sont aussi préparés page par page pour le mode concert.
    final booklets = _data.booklets.where((b) => b.pdfPath != null).toList();
    final total = files.length + booklets.length;
    final media = MediaQuery.of(context);
    final width = PageImages.widthFor(media.size.width, media.size.height, media.devicePixelRatio);
    final progress = ValueNotifier(0);
    final step = ValueNotifier('Téléchargement des fichiers');
    var failed = 0;
    var cancelled = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Téléchargement'),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, n, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: total == 0 ? 1 : n / total),
            const SizedBox(height: 12),
            Text('${step.value} · $n / $total'),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(ctx);
            },
            child: const Text('Arrêter'),
          ),
        ],
      ),
    );
    for (final (bucket, path) in files) {
      if (cancelled) return;
      try {
        await FileStore.instance.load(bucket, path);
      } catch (_) {
        failed++;
      }
      progress.value++;
    }
    step.value = 'Préparation des livrets';
    for (final b in booklets) {
      if (cancelled) return;
      final pages = PageImages(bucket: Repository.bookletsBucket, path: b.pdfPath!, width: width);
      await pages.start();
      pages.dispose();
      progress.value++;
    }
    if (!mounted || cancelled) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed == 0
          ? 'Tout est gardé sur cet appareil : ${files.length} fichiers, livrets prêts pour le mode concert.'
          : '${files.length - failed} fichiers gardés, $failed n\'ont pas pu être téléchargés.'),
    ));
  }

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
                _Tab.recordings => RecordingsScreen(backend: _work, agenda: _agenda, canEdit: _canEdit),
                _Tab.inventory => InventoryScreen(backend: _work, canEdit: _canEdit),
                _Tab.members => widget.membersPanel ?? const MembersPanel(),
              };

    final destinations = [
      for (final t in _tabs)
        switch (t) {
          _Tab.home => (Icons.home_outlined, Icons.home_rounded, 'Accueil'),
          _Tab.songs => (Icons.library_music_outlined, Icons.library_music_rounded, 'Chants'),
          _Tab.agenda => (Icons.event_outlined, Icons.event_rounded, 'Agenda'),
          _Tab.booklets => (Icons.menu_book_outlined, Icons.menu_book_rounded, 'Livrets'), // dans l'onglet Chants
          _Tab.recordings => (Icons.mic_none_rounded, Icons.mic_rounded, 'Répètes'),
          _Tab.inventory => (Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Inventaire'),
          _Tab.members => (Icons.groups_outlined, Icons.groups_rounded, 'Membres'),
        },
    ];
    // Les livrets sont dans l'onglet Chants.
    final index = _tabs.indexOf(_tab == _Tab.booklets ? _Tab.songs : _tab);
    void select(int i) => setState(() {
          _tab = _tabs[i];
          if (_tab == _Tab.songs && i != index) _categoryFilter = null;
        });

    final fab = _fab();
    final page = Column(children: [
      ValueListenableBuilder<bool>(
        valueListenable: Offline.isOffline,
        builder: (context, offline, _) => !offline
            ? const SizedBox.shrink()
            : Material(
                color: AppColors.aubergine,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      const Icon(Icons.cloud_off_rounded, color: AppColors.goldLight, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Hors connexion : tu vois les dernières données enregistrées',
                            style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 12.5)),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: AppColors.goldLight),
                        onPressed: _load,
                        child: const Text('Réessayer'),
                      ),
                    ]),
                  ),
                ),
              ),
      ),
      Expanded(child: body),
    ]);
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
          Expanded(child: SafeArea(child: page)),
        ]),
      );
    }
    // Beaucoup d'onglets : noms en plus petit pour qu'ils tiennent tous.
    final small = destinations.length > 5;
    return Scaffold(
      floatingActionButton: fab,
      body: SafeArea(bottom: false, child: page),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarTheme.of(context).copyWith(
          labelTextStyle: small
              ? WidgetStatePropertyAll(Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10.5, letterSpacing: 0))
              : null,
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: select,
          destinations: [
            for (final d in destinations)
              NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
          ],
        ),
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

  final _announcementsKey = GlobalKey<AnnouncementsSectionState>();

  Widget _homeTab(bool wide) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        _hero(),
        ContentWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            NextEventsSection(
              profile: widget.profile,
              backend: _agenda,
              onOpenAgenda: () => setState(() => _tab = _Tab.agenda),
              links: _links,
            ),
            _shortcuts(),
            AnnouncementsSection(key: _announcementsKey, profile: widget.profile, backend: _agenda),
            const SizedBox(height: 8),
            const InstallCard(),
          ]),
        ),
      ]),
    );
  }

  /// Bandeau compact : logo, bonjour et date, compte.
  Widget _hero() {
    final firstName = widget.profile.fullName.trim().split(' ').first;
    final today = DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now());
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Stack(children: [
        Positioned(
          right: 70,
          top: -24,
          child: Icon(Icons.music_note_rounded, size: 110, color: Colors.white.withValues(alpha: 0.06)),
        ),
        ContentWidth(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 14),
              child: Row(children: [
                const AppLogo(size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(firstName.isEmpty ? 'Bonjour !' : 'Bonjour $firstName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'DMSerifDisplay', color: Colors.white, fontSize: 22, height: 1.15)),
                    Text(_capitalize(today),
                        style: TextStyle(fontFamily: 'Poppins', color: AppColors.goldLight.withValues(alpha: 0.95), fontSize: 12.5)),
                  ]),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Mon compte',
                  onSelected: (v) {
                    if (v == 'logout') Supabase.instance.client.auth.signOut();
                    if (v == 'password') {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (ctx) => NewPasswordScreen(onDone: () => Navigator.of(ctx).pop())));
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(enabled: false, child: Text('${widget.profile.fullName} · ${roleLabel(widget.profile.role)}')),
                    const PopupMenuItem(value: 'password', child: Text('Changer mon mot de passe')),
                    const PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
                  ],
                  child: Avatar(widget.profile.fullName, radius: 18),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  /// Raccourcis compacts : outils pour tous, créations du chef de chœur regroupées dans « Créer ».
  Widget _shortcuts() {
    final tint = Theme.of(context).colorScheme.tertiary;
    Widget chip(IconData icon, String label, VoidCallback onTap) => ActionChip(
          avatar: Icon(icon, size: 18, color: tint),
          label: Text(label),
          onPressed: onTap,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        chip(Icons.tune_rounded, 'Diapason', () => _openTools(0)),
        chip(Icons.timer_outlined, 'Métronome', () => _openTools(1)),
        if (_canEdit)
          MenuAnchor(
            builder: (context, menu, _) => chip(Icons.add_rounded, 'Créer', () => menu.isOpen ? menu.close() : menu.open()),
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.campaign_rounded),
                onPressed: () => _announcementsKey.currentState?.write(),
                child: const Text('Une annonce'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.library_add_rounded),
                onPressed: () => _openSongForm(),
                child: const Text('Un chant'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.auto_stories_rounded),
                onPressed: () => _openBookletEditor(),
                child: const Text('Un livret'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.upload_file_rounded),
                onPressed: _importBooklet,
                child: const Text('Importer un livret PDF'),
              ),
            ],
          ),
      ]),
    );
  }


  // ---------- Chants ----------

  /// Haut de l'onglet Chants : bascule entre les chants et les livrets.
  Widget _libraryHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: SegmentedButton<_Tab>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Tab.songs, icon: Icon(Icons.library_music_rounded), label: Text('Chants')),
            ButtonSegment(value: _Tab.booklets, icon: Icon(Icons.menu_book_rounded), label: Text('Livrets')),
          ],
          selected: {_tab},
          onSelectionChanged: (v) => setState(() => _tab = v.first),
        ),
      );

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
            _libraryHeader(),
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
            _libraryHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Les programmes de vos prestations',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            if (_data.booklets.any((b) => b.pdfPath != null) || _data.songs.any((s) => s.hasPdf))
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download_for_offline_rounded),
                    label: const Text('Tout garder sur cet appareil'),
                    onPressed: _downloadAll,
                  ),
                ),
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
