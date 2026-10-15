import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../platform/pick_file.dart';
import '../services/errors.dart';
import '../services/file_store.dart';
import '../services/workshop.dart';
import '../widgets/ui.dart';
import 'inventory_screen.dart' show StoredPhoto;
import 'outfits_screen.dart';

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
              child: SizedBox(width: 110, height: 110, child: OutfitPhoto(widget.garment?.photoPath, fresh: _photo)),
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
        icon: outfitIcon,
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
                    child: StoredPhoto(g.photoPath, icon: outfitIcon),
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
