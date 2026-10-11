import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../platform/pick_file.dart';
import '../services/file_store.dart';
import '../services/workshop.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'inventory_screen.dart' show StoredPhoto;

const _outfitIcon = Icons.checkroom_rounded;

/// Photo d'une tenue ou d'un élément (ou celle qu'on vient de choisir, pas encore envoyée).
class _Photo extends StatelessWidget {
  final String? path;
  final Uint8List? fresh;

  const _Photo(this.path, {this.fresh});

  @override
  Widget build(BuildContext context) => fresh != null
      ? Image.memory(fresh!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
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
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(aspectRatio: compact ? 16 / 9 : 4 / 3, child: StoredPhoto(outfit.photoPath, icon: _outfitIcon)),
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

class _OutfitsScreenState extends State<OutfitsScreen> {
  List<Outfit>? _outfits;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await widget.backend.outfits();
      if (mounted) setState(() => _outfits = o);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outfits = _outfits;
    return Scaffold(
      appBar: AppBar(title: const Text('Tenues')),
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_rounded), label: const Text('Nouvelle tenue'), onPressed: () => _edit())
          : null,
      body: outfits == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text('Chargement impossible.\n$_error'))
          : outfits.isEmpty
              ? EmptyState(
                  icon: _outfitIcon,
                  title: 'Aucune tenue',
                  message: widget.canEdit
                      ? 'Crée une tenue avec sa photo et ses éléments (chemise, pantalon…), puis choisis-la pour une prestation.'
                      : 'Les tenues du groupe apparaîtront ici.',
                )
              : RefreshIndicator(
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
                ),
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

class _ItemDraft {
  final TextEditingController label;
  String? photoPath;
  Uint8List? fresh;

  _ItemDraft(String text, this.photoPath) : label = TextEditingController(text: text);
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
  static const _suggestions = [
    'Chemise noire',
    'Pantalon noir',
    'Ceinture noire',
    'Chaussettes noires',
    'Chaussures noires',
    'Veste',
    'Cravate',
    'Foulard',
  ];

  late final _name = TextEditingController(text: widget.outfit?.name);
  late final _notes = TextEditingController(text: widget.outfit?.notes);
  late final String? _photoPath = widget.outfit?.photoPath;
  Uint8List? _photo;
  late final List<_ItemDraft> _items = [for (final i in widget.outfit?.items ?? const <OutfitItem>[]) _ItemDraft(i.label, i.photoPath)];
  bool _saving = false;

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Donne un nom à la tenue (ex. Tenue noire).')));
      return;
    }
    setState(() => _saving = true);
    try {
      final photo = await _upload(_photo, _photoPath);
      final items = <OutfitItem>[];
      for (final d in _items) {
        if (d.label.text.trim().isEmpty) continue;
        items.add(OutfitItem(label: d.label.text.trim(), photoPath: await _upload(d.fresh, d.photoPath)));
      }
      await widget.backend.saveOutfit(
          id: widget.outfit?.id, name: _name.text, notes: _notes.text, photoPath: photo, items: items);
      // Photos remplacées ou retirées : on ne les garde pas en ligne.
      final kept = {photo, for (final i in items) i.photoPath};
      final old = [widget.outfit?.photoPath, for (final i in widget.outfit?.items ?? const <OutfitItem>[]) i.photoPath];
      for (final p in old.whereType<String>().where((p) => !kept.contains(p))) {
        await widget.backend.deleteFile(WorkBackend.photosBucket, p).catchError((_) {});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = _items.map((i) => i.label.text.trim().toLowerCase()).toSet();
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
                child: AspectRatio(
                  aspectRatio: 4 / 3,
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
              decoration: const InputDecoration(labelText: 'Remarque (facultatif)', hintText: 'Ex. Chemise bien repassée'),
            ),
            const SizedBox(height: 20),
            Text('Éléments de la tenue', style: theme.textTheme.titleMedium),
            Text('Une petite photo par élément, pour comprendre la tenue d\'un coup d\'œil.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            for (final (i, d) in _items.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final b = await _pick();
                      if (b != null) setState(() => d.fresh = b);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(width: 64, height: 64, child: _Photo(d.photoPath, fresh: d.fresh)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: d.label,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(hintText: 'Ex. Chemise noire'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _items.removeAt(i)),
                  ),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Ajouter un élément'),
                onPressed: () => setState(() => _items.add(_ItemDraft('', null))),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in _suggestions.where((s) => !used.contains(s.toLowerCase())))
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 16),
                  label: Text(s),
                  onPressed: () => setState(() => _items.add(_ItemDraft(s, null))),
                ),
            ]),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tenue non enregistrée : $e')));
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
