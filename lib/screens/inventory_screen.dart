import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/file_store.dart';
import '../services/workshop.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Photo gardée sur l'appareil après le premier affichage (visible hors connexion).
class StoredPhoto extends StatelessWidget {
  final String? path;
  final BoxFit fit;

  const StoredPhoto(this.path, {super.key, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.aubergine.withValues(alpha: 0.08),
      child: const Center(child: Icon(Icons.inventory_2_outlined, size: 36, color: AppColors.aubergineLight)),
    );
    if (path == null) return placeholder;
    return FutureBuilder<Uint8List>(
      future: FileStore.instance.load(WorkBackend.photosBucket, path!),
      builder: (context, snap) => snap.hasData
          ? Image.memory(snap.data!, fit: fit, gaplessPlayback: true, width: double.infinity, height: double.infinity)
          : placeholder,
    );
  }
}

/// Inventaire du matériel du local : fiches produits classées par catégorie.
class InventoryScreen extends StatefulWidget {
  final WorkBackend backend;
  final bool canEdit;

  const InventoryScreen({super.key, required this.backend, required this.canEdit});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<EquipmentCategory> _categories = const [];
  List<EquipmentItem>? _items;
  String? _filter;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([widget.backend.equipmentCategories(), widget.backend.equipment()]);
      if (!mounted) return;
      setState(() {
        _categories = r[0] as List<EquipmentCategory>;
        _items = r[1] as List<EquipmentItem>;
        _error = null;
        if (_filter != null && !_categories.any((c) => c.id == _filter)) _filter = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String? _categoryName(String? id) => _categories.where((c) => c.id == id).firstOrNull?.name;

  Future<void> _edit([EquipmentItem? item]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EquipmentFormScreen(
          backend: widget.backend,
          categories: _categories,
          item: item,
          initialCategoryId: item == null ? _filter : null,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _open(EquipmentItem item) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EquipmentDetailScreen(
          item: item,
          categoryName: _categoryName(item.categoryId),
          canEdit: widget.canEdit,
          onEdit: () => _edit(item),
          onDelete: () => widget.backend.deleteEquipment(item),
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _manageCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CategoriesSheet(backend: widget.backend, categories: _categories),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = (_items ?? const <EquipmentItem>[])
        .where((i) => _filter == null || i.categoryId == _filter)
        .where((i) => _query.isEmpty || i.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final total = (_items ?? const <EquipmentItem>[]).fold<int>(0, (n, i) => n + i.quantity);
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventaire'),
        actions: [
          if (widget.canEdit)
            IconButton(
              tooltip: 'Gérer les catégories',
              icon: const Icon(Icons.category_outlined),
              onPressed: _manageCategories,
            ),
        ],
      ),
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter'),
              onPressed: () => _edit(),
            )
          : null,
      body: _items == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text('Chargement impossible.\n$_error', textAlign: TextAlign.center))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
                ContentWidth(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: 'Rechercher un produit…',
                        ),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ),
                    SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        children: [
                          ChoiceChip(
                            label: Text('Tout (${_items!.length})'),
                            selected: _filter == null,
                            onSelected: (_) => setState(() => _filter = null),
                          ),
                          for (final c in _categories)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ChoiceChip(
                                label: Text('${c.name} (${_items!.where((i) => i.categoryId == c.id).length})'),
                                selected: _filter == c.id,
                                onSelected: (_) => setState(() => _filter = c.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Text('${_items!.length} produits · $total pièces au total',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    if (items.isEmpty)
                      EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: _items!.isEmpty ? 'Inventaire vide' : 'Aucun produit',
                        message: _items!.isEmpty
                            ? (widget.canEdit
                                ? 'Crée tes catégories (Enceintes, Micros…) puis ajoute le matériel du local avec une photo.'
                                : 'Le matériel du local apparaîtra ici.')
                            : 'Rien ne correspond dans cette catégorie.',
                        action: _items!.isEmpty && widget.canEdit && _categories.isEmpty
                            ? FilledButton.icon(
                                icon: const Icon(Icons.category_outlined),
                                label: const Text('Créer les catégories'),
                                onPressed: _manageCategories,
                              )
                            : null,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GridView.count(
                          crossAxisCount: width >= 1000 ? 5 : (width >= 700 ? 4 : 2),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.78,
                          children: [for (final i in items) _card(i)],
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
    );
  }

  Widget _card(EquipmentItem item) {
    final theme = Theme.of(context);
    final cat = _categoryName(item.categoryId);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _open(item),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              Hero(tag: 'materiel-${item.id}', child: StoredPhoto(item.photoPath)),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.aubergine, borderRadius: BorderRadius.circular(20)),
                  child: Text('× ${item.quantity}',
                      style: const TextStyle(fontFamily: 'Poppins', color: AppColors.goldLight, fontWeight: FontWeight.w600, fontSize: 12.5)),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              if (cat != null)
                Text(cat,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Fiche produit.
class EquipmentDetailScreen extends StatelessWidget {
  final EquipmentItem item;
  final String? categoryName;
  final bool canEdit;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;

  const EquipmentDetailScreen({
    super.key,
    required this.item,
    this.categoryName,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(IconData icon, String label, String value) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: theme.colorScheme.tertiary),
          title: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          subtitle: Text(value, style: theme.textTheme.titleMedium),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          if (canEdit) ...[
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () {
                Navigator.pop(context, false);
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
                    content: Text('Supprimer « ${item.name} » de l\'inventaire ?'),
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
      body: ListView(children: [
        ContentWidth(
          maxWidth: 640,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (item.photoPath != null)
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      backgroundColor: Colors.black,
                      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                      body: InteractiveViewer(maxScale: 5, child: Center(child: StoredPhoto(item.photoPath, fit: BoxFit.contain))),
                    ),
                  ),
                ),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Hero(tag: 'materiel-${item.id}', child: StoredPhoto(item.photoPath)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(item.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                row(Icons.category_outlined, 'Catégorie', categoryName ?? 'Sans catégorie'),
                row(Icons.numbers_rounded, 'Quantité', '${item.quantity}'),
                row(Icons.sticky_note_2_outlined, 'Remarque', item.notes ?? '—'),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Création ou modification d'une fiche produit.
class EquipmentFormScreen extends StatefulWidget {
  final WorkBackend backend;
  final List<EquipmentCategory> categories;
  final EquipmentItem? item;
  final String? initialCategoryId;

  const EquipmentFormScreen({
    super.key,
    required this.backend,
    required this.categories,
    this.item,
    this.initialCategoryId,
  });

  @override
  State<EquipmentFormScreen> createState() => _EquipmentFormScreenState();
}

class _EquipmentFormScreenState extends State<EquipmentFormScreen> {
  late final _name = TextEditingController(text: widget.item?.name);
  late final _notes = TextEditingController(text: widget.item?.notes);
  late List<EquipmentCategory> _categories = [...widget.categories];
  late String? _categoryId = widget.item?.categoryId ?? widget.initialCategoryId;
  late int _quantity = widget.item?.quantity ?? 1;
  late String? _photoPath = widget.item?.photoPath;
  Uint8List? _newPhoto;
  bool _saving = false;

  Future<void> _pickPhoto() async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null) return;
    final bytes = await shrinkImage(await f.readAsBytes(), 1600);
    setState(() => _newPhoto = bytes);
  }

  Future<void> _newCategory() async {
    final name = await askText(context, title: 'Nouvelle catégorie', hint: 'Ex. Enceintes, Micros, Câbles…');
    if (name == null) return;
    try {
      final c = await widget.backend.addEquipmentCategory(name);
      setState(() {
        _categories = [..._categories, c]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _categoryId = c.id;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Catégorie non créée : $e')));
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Donne un nom au produit.')));
      return;
    }
    setState(() => _saving = true);
    try {
      var path = _photoPath;
      final old = widget.item?.photoPath;
      if (_newPhoto != null) {
        path = await widget.backend.upload(WorkBackend.photosBucket, 'photo.jpg', _newPhoto!, 'image/jpeg');
        await FileStore.instance.keep(WorkBackend.photosBucket, path, _newPhoto!);
      }
      await widget.backend.saveEquipment(
        id: widget.item?.id,
        name: _name.text,
        categoryId: _categoryId,
        quantity: _quantity,
        notes: _notes.text,
        photoPath: path,
      );
      // Ancienne photo remplacée ou retirée : on ne la garde pas en ligne.
      if (old != null && old != path) {
        await widget.backend.deleteFile(WorkBackend.photosBucket, old).catchError((_) {});
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
    final hasPhoto = _newPhoto != null || _photoPath != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? 'Nouveau produit' : 'Modifier le produit'),
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
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        ContentWidth(
          maxWidth: 640,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Photo
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Material(
                    color: AppColors.aubergine.withValues(alpha: 0.06),
                    child: InkWell(
                      onTap: _pickPhoto,
                      child: Stack(fit: StackFit.expand, children: [
                        if (_newPhoto != null)
                          Image.memory(_newPhoto!, fit: BoxFit.cover)
                        else if (_photoPath != null)
                          StoredPhoto(_photoPath)
                        else
                          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.add_a_photo_outlined, size: 40, color: theme.colorScheme.tertiary),
                            const SizedBox(height: 8),
                            const Text('Ajouter une photo'),
                          ]),
                        if (hasPhoto)
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Row(children: [
                              FilledButton.tonalIcon(
                                icon: const Icon(Icons.photo_camera_rounded),
                                label: const Text('Changer'),
                                onPressed: _pickPhoto,
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: 'Retirer la photo',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => setState(() {
                                  _newPhoto = null;
                                  _photoPath = null;
                                }),
                              ),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nom du produit', hintText: 'Ex. Micro Shure SM58'),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                    decoration: const InputDecoration(labelText: 'Catégorie'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Sans catégorie')),
                      for (final c in _categories) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Nouvelle catégorie',
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: _newCategory,
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text('Quantité', style: theme.textTheme.titleMedium)),
                IconButton.filledTonal(
                  onPressed: _quantity > 0 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 56,
                  child: Text('$_quantity', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                ),
                IconButton.filledTonal(
                  onPressed: () => setState(() => _quantity++),
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Remarque',
                  hintText: 'Ex. pile 9 V à changer, câble XLR fourni, rangé dans la caisse bleue…',
                  alignLabelWithHint: true,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Petite fenêtre pour saisir un texte (nom de catégorie…).
Future<String?> askText(BuildContext context, {required String title, String? hint, String? initial}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('OK')),
      ],
    ),
  );
  return (value == null || value.isEmpty) ? null : value;
}

/// Création, renommage et suppression des catégories de matériel.
class _CategoriesSheet extends StatefulWidget {
  final WorkBackend backend;
  final List<EquipmentCategory> categories;

  const _CategoriesSheet({required this.backend, required this.categories});

  @override
  State<_CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends State<_CategoriesSheet> {
  late List<EquipmentCategory> _items = [...widget.categories];

  Future<void> _reload() async {
    final c = await widget.backend.equipmentCategories();
    if (mounted) setState(() => _items = c);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(children: [
              Expanded(child: Text('Catégories de matériel', style: Theme.of(context).textTheme.titleLarge)),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Ajouter'),
                onPressed: () async {
                  final name = await askText(context, title: 'Nouvelle catégorie', hint: 'Ex. Enceintes, Micros, Câbles…');
                  if (name != null) _run(() => widget.backend.addEquipmentCategory(name));
                },
              ),
            ]),
          ),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Aucune catégorie pour l\'instant. Ajoute par exemple Enceintes, Micros, Câbles, Pupitres.'),
            ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final c in _items)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(c.name),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Renommer',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final name = await askText(context, title: 'Renommer la catégorie', initial: c.name);
                        if (name != null) _run(() => widget.backend.renameEquipmentCategory(c.id, name));
                      },
                    ),
                    IconButton(
                      tooltip: 'Supprimer',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            content: Text('Supprimer la catégorie « ${c.name} » ? Les produits restent dans l\'inventaire, sans catégorie.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
                            ],
                          ),
                        );
                        if (ok == true) _run(() => widget.backend.deleteEquipmentCategory(c.id));
                      },
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }
}
