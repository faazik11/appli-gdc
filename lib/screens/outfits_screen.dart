import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../platform/pick_file.dart';
import '../services/errors.dart';
import '../services/file_store.dart';
import '../services/workshop.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'inventory_screen.dart' show StoredPhoto, WholeImage, openPhoto;

const _outfitIcon = Icons.checkroom_rounded;

/// Photo d'une tenue ou d'un élément (ou celle qu'on vient de choisir, pas encore envoyée).
class _Photo extends StatelessWidget {
  final String? path;
  final Uint8List? fresh;

  const _Photo(this.path, {this.fresh});

  @override
  Widget build(BuildContext context) => fresh != null
      ? WholeImage(fresh!)
      : StoredPhoto(path, icon: _outfitIcon);
}

/// Affichage visuel d'une tenue : grande photo, puis chaque élément en petite vignette.
class OutfitView extends StatelessWidget {
  final Outfit outfit;
  final bool compact;

  const OutfitView(this.outfit, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (outfit.photoPath != null)
        // Photo en hauteur (mannequin, tenue complète) : montrée en entier, touchée = plein écran.
        GestureDetector(
          onTap: () => openPhoto(context, outfit.photoPath!),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(height: compact ? 300 : 460, child: StoredPhoto(outfit.photoPath, icon: _outfitIcon)),
          ),
        ),
      if (outfit.notes != null) ...[
        const SizedBox(height: 10),
        Text(outfit.notes!, style: theme.textTheme.bodyMedium),
      ],
      if (outfit.items.isNotEmpty) ...[
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final perRow = c.maxWidth > 560 ? 5 : (c.maxWidth > 360 ? 4 : 3);
          final size = (c.maxWidth - (perRow - 1) * 10) / perRow;
          return Wrap(spacing: 10, runSpacing: 12, children: [
            for (final item in outfit.items)
              SizedBox(
                width: size,
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(width: size, height: size, child: StoredPhoto(item.photoPath, icon: _outfitIcon)),
                  ),
                  const SizedBox(height: 6),
                  Text(item.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
          ]);
        }),
      ],
    ]);
  }
}

/// Liste des tenues du groupe.
class OutfitsScreen extends StatefulWidget {
  final WorkBackend backend;
  final bool canEdit;

  const OutfitsScreen({super.key, required this.backend, required this.canEdit});

  @override
  State<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends State<OutfitsScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
  final _garmentsKey = GlobalKey<GarmentsListState>();
  List<Outfit>? _outfits;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await widget.backend.outfits();
      if (mounted) setState(() => _outfits = o);
    } catch (e) {
      if (mounted) setState(() => _error = explain(e));
    }
  }

  Future<void> _edit([Outfit? o]) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => OutfitFormScreen(backend: widget.backend, outfit: o)));
    if (saved == true) _load();
  }

  Future<void> _open(Outfit o) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OutfitDetailScreen(
          outfit: o,
          canEdit: widget.canEdit,
          onEdit: () => _edit(o),
          onDelete: () => widget.backend.deleteOutfit(o),
        ),
      ),
    );
    if (changed == true) _load();
  }

  Widget _outfitList(BuildContext context) {
    final theme = Theme.of(context);
    final outfits = _outfits;
    if (outfits == null) {
      return Center(
          child: _error == null ? const CircularProgressIndicator() : Text('Chargement impossible.\n$_error'));
    }
    if (outfits.isEmpty) {
      return EmptyState(
        icon: _outfitIcon,
        title: 'Aucune tenue',
        message: widget.canEdit
            ? 'Crée une tenue avec sa photo et ses vêtements, puis choisis-la pour une prestation.'
            : 'Les tenues du groupe apparaîtront ici.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 100), children: [
        for (final o in outfits)
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(o),
              child: Row(children: [
                SizedBox(width: 96, height: 96, child: StoredPhoto(o.photoPath, icon: _outfitIcon)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(o.items.map((i) => i.label).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded),
                const SizedBox(width: 8),
              ]),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onGarments = _tabs.index == 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tenues'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Tenues'), Tab(text: 'Vêtements')]),
      ),
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_rounded),
              label: Text(onGarments ? 'Nouveau vêtement' : 'Nouvelle tenue'),
              onPressed: () => onGarments ? _garmentsKey.currentState?.edit() : _edit(),
            )
          : null,
      body: TabBarView(controller: _tabs, children: [
        _outfitList(context),
        GarmentsList(
          key: _garmentsKey,
          backend: widget.backend,
          canEdit: widget.canEdit,
          // Un vêtement modifié change aussi l'affichage des tenues
          onChanged: _load,
        ),
      ]),
    );
  }
}

/// Fenêtre de création ou modification d'un vêtement (nom + photo). Renvoie le vêtement enregistré,
/// ou null si rien n'a changé ; [deleted] est appelé si le vêtement a été supprimé.
Future<Garment?> editGarment(BuildContext context, WorkBackend backend, {Garment? garment, VoidCallback? deleted}) {
  return showModalBottomSheet<Garment>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GarmentSheet(backend: backend, garment: garment, deleted: deleted),
  );
}

class _GarmentSheet extends StatefulWidget {
  final WorkBackend backend;
  final Garment? garment;
  final VoidCallback? deleted;

  const _GarmentSheet({required this.backend, this.garment, this.deleted});

  @override
  State<_GarmentSheet> createState() => _GarmentSheetState();
}

class _GarmentSheetState extends State<_GarmentSheet> {
  late final _name = TextEditingController(text: widget.garment?.name);
  Uint8List? _photo;
  bool _busy = false;

  Future<void> _pick() async {
    final f = await pickOneFile(type: FileType.image);
    if (f == null) return;
    final b = await shrinkImage(await f.readAsBytes(), 1200);
    if (mounted) setState(() => _photo = b);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Donne un nom au vêtement (ex. Chemise blanche).')));
      return;
    }
    setState(() => _busy = true);
    try {
      final old = widget.garment?.photoPath;
      var path = old;
      if (_photo != null) {
        path = await widget.backend.upload(WorkBackend.photosBucket, 'vetement.jpg', _photo!, 'image/jpeg');
        await FileStore.instance.keep(WorkBackend.photosBucket, path, _photo!);
      }
      final g = await widget.backend.saveGarment(id: widget.garment?.id, name: _name.text, photoPath: path);
      if (old != null && old != path) await widget.backend.deleteFile(WorkBackend.photosBucket, old).catchError((_) {});
      if (mounted) Navigator.pop(context, g);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : ${explain(e)}')));
      }
    }
  }

  Future<void> _delete() async {
    final g = widget.garment!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('Supprimer « ${g.name} » ? Il sera aussi retiré des tenues qui l\'utilisent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.backend.deleteGarment(g);
      widget.deleted?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Suppression impossible : ${explain(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhoto = _photo != null || widget.garment?.photoPath != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.garment == null ? 'Nouveau vêtement' : 'Modifier le vêtement', style: theme.textTheme.titleLarge),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _busy ? null : _pick,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(width: 110, height: 110, child: _Photo(widget.garment?.photoPath, fresh: _photo)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _name,
                autofocus: widget.garment == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nom', hintText: 'Ex. Chemise blanche'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: Text(hasPhoto ? 'Changer la photo' : 'Ajouter une photo'),
                ),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          if (widget.garment != null)
            TextButton.icon(
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Supprimer'),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            ),
          const Spacer(),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enregistrer'),
          ),
        ]),
      ]),
    );
  }
}

/// Grille des vêtements : photo et nom ; les référents ajoutent, modifient et suppriment.
class GarmentsList extends StatefulWidget {
  final WorkBackend backend;
  final bool canEdit;
  final VoidCallback onChanged;

  const GarmentsList({super.key, required this.backend, required this.canEdit, required this.onChanged});

  @override
  State<GarmentsList> createState() => GarmentsListState();
}

class GarmentsListState extends State<GarmentsList> {
  List<Garment>? _garments;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final g = await widget.backend.garments();
      if (mounted) setState(() => _garments = g);
    } catch (e) {
      if (mounted) setState(() => _error = explain(e));
    }
  }

  Future<void> edit([Garment? g]) async {
    var changed = false;
    final saved = await editGarment(context, widget.backend, garment: g, deleted: () => changed = true);
    if (saved != null || changed) {
      await _load();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final garments = _garments;
    if (garments == null) {
      return Center(
          child: _error == null ? const CircularProgressIndicator() : Text('Chargement impossible.\n$_error'));
    }
    if (garments.isEmpty) {
      return EmptyState(
        icon: _outfitIcon,
        title: 'Aucun vêtement',
        message: widget.canEdit
            ? 'Ajoute les vêtements (chemise blanche, chaussettes noires…) avec leur photo, puis compose les tenues avec.'
            : 'Les vêtements des tenues apparaîtront ici.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth > 900 ? 6 : (c.maxWidth > 600 ? 4 : 3);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: perRow, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 0.78),
          itemCount: garments.length,
          itemBuilder: (context, i) {
            final g = garments[i];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.canEdit ? () => edit(g) : null,
              child: Column(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: StoredPhoto(g.photoPath, icon: _outfitIcon),
                  ),
                ),
                const SizedBox(height: 6),
                Text(g.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ]),
            );
          },
        );
      }),
    );
  }
}

class OutfitDetailScreen extends StatelessWidget {
  final Outfit outfit;
  final bool canEdit;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;

  const OutfitDetailScreen(
      {super.key, required this.outfit, required this.canEdit, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(outfit.name),
        actions: [
          if (canEdit) ...[
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: Text('Supprimer la tenue « ${outfit.name} » ?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
                    ],
                  ),
                );
                if (ok != true) return;
                await onDelete();
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
          ],
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 40), children: [
        ContentWidth(maxWidth: 700, child: OutfitView(outfit)),
      ]),
    );
  }
}

/// Création ou modification d'une tenue.
class OutfitFormScreen extends StatefulWidget {
  final WorkBackend backend;
  final Outfit? outfit;

  const OutfitFormScreen({super.key, required this.backend, this.outfit});

  @override
  State<OutfitFormScreen> createState() => _OutfitFormScreenState();
}

class _OutfitFormScreenState extends State<OutfitFormScreen> {
  late final _name = TextEditingController(text: widget.outfit?.name);
  late final _notes = TextEditingController(text: widget.outfit?.notes);
  late final String? _photoPath = widget.outfit?.photoPath;
  Uint8List? _photo;
  late final List<OutfitItem> _items = [...?widget.outfit?.items];
  List<Garment>? _garments;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadGarments();
  }

  Future<void> _loadGarments() async {
    try {
      final g = await widget.backend.garments();
      if (mounted) setState(() => _garments = g);
    } catch (_) {
      if (mounted) setState(() => _garments = const []);
    }
  }

  /// Choix des vêtements de la tenue dans la liste (on peut en créer un au passage).
  Future<void> _chooseGarments() async {
    final chosen = {for (final i in _items) i.garmentId}.whereType<String>().toSet();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, setSheet) {
        final garments = _garments ?? const <Garment>[];
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(children: [
                  Expanded(child: Text('Vêtements de la tenue', style: Theme.of(context).textTheme.titleLarge)),
                  FilledButton(onPressed: () => Navigator.pop(sheet, chosen), child: const Text('Valider')),
                ]),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
                  for (final g in garments)
                    CheckboxListTile(
                      value: chosen.contains(g.id),
                      onChanged: (v) => setSheet(() => v == true ? chosen.add(g.id) : chosen.remove(g.id)),
                      secondary: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(width: 48, height: 48, child: StoredPhoto(g.photoPath, icon: _outfitIcon)),
                      ),
                      title: Text(g.name),
                    ),
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.add_rounded)),
                    title: const Text('Nouveau vêtement'),
                    onTap: () async {
                      final g = await editGarment(context, widget.backend);
                      if (g == null) return;
                      await _loadGarments();
                      setSheet(() => chosen.add(g.id));
                    },
                  ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
    if (result == null || !mounted) return;
    final byId = {for (final g in _garments ?? const <Garment>[]) g.id: g};
    setState(() {
      // On garde l'ordre déjà choisi, les nouveaux vêtements vont à la fin
      _items.removeWhere((i) => i.garmentId != null && !result.contains(i.garmentId));
      final present = _items.map((i) => i.garmentId).toSet();
      for (final id in result.where((id) => !present.contains(id))) {
        final g = byId[id];
        if (g != null) _items.add(OutfitItem.fromGarment(g));
      }
    });
  }

  Future<Uint8List?> _pick() async {
    final f = await pickOneFile(type: FileType.image);
    if (f == null) return null;
    return shrinkImage(await f.readAsBytes(), 1200);
  }

  Future<void> _pickMain() async {
    final b = await _pick();
    if (b != null) setState(() => _photo = b);
  }

  Future<String?> _upload(Uint8List? fresh, String? path) async {
    if (fresh == null) return path;
    final p = await widget.backend.upload(WorkBackend.photosBucket, 'tenue.jpg', fresh, 'image/jpeg');
    await FileStore.instance.keep(WorkBackend.photosBucket, p, fresh);
    return p;
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Donne un nom à la tenue (ex. Tenue noire).')));
      return;
    }
    setState(() => _saving = true);
    try {
      final photo = await _upload(_photo, _photoPath);
      await widget.backend
          .saveOutfit(id: widget.outfit?.id, name: _name.text, notes: _notes.text, photoPath: photo, items: _items);
      // Photos remplacées ou retirées : on ne les garde pas en ligne (celles des vêtements restent).
      final kept = {photo, for (final i in _items) i.photoPath};
      final old = [
        widget.outfit?.photoPath,
        for (final i in widget.outfit?.items ?? const <OutfitItem>[])
          if (i.garmentId == null) i.photoPath,
      ];
      for (final p in old.whereType<String>().where((p) => !kept.contains(p))) {
        await widget.backend.deleteFile(WorkBackend.photosBucket, p).catchError((_) {});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : ${explain(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.outfit == null ? 'Nouvelle tenue' : 'Modifier la tenue'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer'),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 60), children: [
        ContentWidth(
          maxWidth: 700,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nom de la tenue', hintText: 'Ex. Tenue noire'),
            ),
            const SizedBox(height: 14),
            Text('Photo de la tenue complète', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickMain,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 380,
                  child: Stack(fit: StackFit.expand, children: [
                    _Photo(_photoPath, fresh: _photo),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: FilledButton.tonalIcon(
                        onPressed: _pickMain,
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: Text(_photo != null || _photoPath != null ? 'Changer' : 'Ajouter une photo'),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notes,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(labelText: 'Remarque (facultatif)', hintText: 'Ex. Chemise bien repassée'),
            ),
            const SizedBox(height: 20),
            Text('Vêtements de la tenue', style: theme.textTheme.titleMedium),
            Text('Choisis-les dans la liste des vêtements (onglet Vêtements), chacun avec sa photo.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) => setState(() => _items.insert(to, _items.removeAt(from))),
              children: [
                for (final (i, item) in _items.indexed)
                  Padding(
                    key: ObjectKey(item),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                            padding: EdgeInsets.only(right: 8), child: Icon(Icons.drag_indicator_rounded)),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(width: 56, height: 56, child: StoredPhoto(item.photoPath, icon: _outfitIcon)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(item.label, style: theme.textTheme.bodyLarge)),
                      IconButton(
                        tooltip: 'Retirer de la tenue',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _items.removeAt(i)),
                      ),
                    ]),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Choisir les vêtements'),
                onPressed: _garments == null ? null : _chooseGarments,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// « Tenue du jour » sur un événement : affichée en images, choisie par les référents.
class EventOutfitSection extends StatefulWidget {
  final String eventId;
  final String? outfitId;
  final WorkBackend work;
  final bool canEdit;
  final VoidCallback onChanged;

  const EventOutfitSection({
    super.key,
    required this.eventId,
    required this.outfitId,
    required this.work,
    required this.canEdit,
    required this.onChanged,
  });

  @override
  State<EventOutfitSection> createState() => _EventOutfitSectionState();
}

class _EventOutfitSectionState extends State<EventOutfitSection> {
  List<Outfit>? _outfits;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await widget.work.outfits();
      if (mounted) setState(() => _outfits = o);
    } catch (_) {
      if (mounted) setState(() => _outfits = const []);
    }
  }

  Future<void> _choose() async {
    final outfits = _outfits ?? const <Outfit>[];
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 16), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Tenue du jour', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final o in outfits)
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 48, height: 48, child: StoredPhoto(o.photoPath, icon: _outfitIcon)),
                ),
                title: Text(o.name),
                subtitle: Text(o.items.map((i) => i.label).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: o.id == widget.outfitId ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(sheet, o),
              ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.add_rounded)),
              title: const Text('Créer une tenue'),
              onTap: () => Navigator.pop(sheet, 'new'),
            ),
            if (widget.outfitId != null)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.block_rounded)),
                title: const Text('Pas de tenue imposée'),
                onTap: () => Navigator.pop(sheet, 'none'),
              ),
          ]),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'new') {
      final saved = await Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => OutfitFormScreen(backend: widget.work)));
      if (saved == true) {
        await _load();
        if (mounted) _choose();
      }
      return;
    }
    try {
      await widget.work.setEventOutfit(widget.eventId, choice is Outfit ? choice.id : null);
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tenue non enregistrée : ${explain(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outfit = _outfits?.where((o) => o.id == widget.outfitId).firstOrNull;
    if (_outfits == null) return const SizedBox.shrink();
    if (outfit == null && !widget.canEdit) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 16),
      Row(children: [
        const Icon(_outfitIcon, size: 20, color: AppColors.aubergine),
        const SizedBox(width: 8),
        Expanded(
          child: Text(outfit == null ? 'Tenue du jour' : 'Tenue du jour : ${outfit.name}',
              style: theme.textTheme.titleMedium),
        ),
        if (widget.canEdit && outfit != null) TextButton(onPressed: _choose, child: const Text('Changer')),
      ]),
      const SizedBox(height: 8),
      if (outfit != null)
        Card(child: Padding(padding: const EdgeInsets.all(12), child: OutfitView(outfit, compact: true)))
      else
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('Choisir la tenue'),
            onPressed: _choose,
          ),
        ),
    ]);
  }
}
