import 'package:flutter/material.dart';

import '../models.dart';
import '../screens/inventory_screen.dart' show StoredPhoto;
import '../services/errors.dart';
import '../services/workshop.dart';
import '../theme.dart';

/// « Matériel à emporter » d'une prestation : choisi dans l'inventaire, coché au chargement.
class EventGearSection extends StatefulWidget {
  final String eventId;
  final WorkBackend work;
  final bool canEdit;

  const EventGearSection({super.key, required this.eventId, required this.work, required this.canEdit});

  @override
  State<EventGearSection> createState() => _EventGearSectionState();
}

class _EventGearSectionState extends State<EventGearSection> {
  List<EquipmentItem> _items = const [];
  List<EquipmentCategory> _categories = const [];
  List<EventGear>? _gear;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([
        widget.work.equipment(),
        widget.work.equipmentCategories(),
        widget.work.eventGear(widget.eventId),
      ]);
      if (!mounted) return;
      setState(() {
        _items = r[0] as List<EquipmentItem>;
        _categories = r[1] as List<EquipmentCategory>;
        _gear = r[2] as List<EventGear>;
      });
    } catch (_) {
      if (mounted) setState(() => _gear = const []);
    }
  }

  EquipmentItem? _item(String id) => _items.where((i) => i.id == id).firstOrNull;

  Future<void> _choose() async {
    final current = {for (final g in _gear ?? const <EventGear>[]) g.equipmentId: g.quantity};
    final picked = await Navigator.of(context).push<Map<String, int>>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _GearPicker(items: _items, categories: _categories, initial: current),
    ));
    if (picked == null) return;
    try {
      await widget.work.setEventGear(widget.eventId, picked);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Matériel non enregistré : ${explain(e)}')));
    }
  }

  Future<void> _toggle(EventGear g) async {
    setState(() => _gear = [
          for (final x in _gear!)
            x.equipmentId == g.equipmentId ? EventGear(equipmentId: x.equipmentId, quantity: x.quantity, packed: !x.packed) : x,
        ]);
    try {
      await widget.work.setGearPacked(widget.eventId, g.equipmentId, !g.packed);
    } catch (e) {
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pas enregistré : ${explain(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gear = (_gear ?? const <EventGear>[]).where((g) => _item(g.equipmentId) != null).toList()
      ..sort((a, b) => _item(a.equipmentId)!.name.toLowerCase().compareTo(_item(b.equipmentId)!.name.toLowerCase()));
    if (_gear == null) return const SizedBox.shrink();
    if (gear.isEmpty && !widget.canEdit) return const SizedBox.shrink();
    final packed = gear.where((g) => g.packed).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Text('Matériel à emporter', style: theme.textTheme.titleMedium)),
        if (gear.isNotEmpty)
          Text(packed == gear.length ? 'Tout est chargé ✓' : '$packed/${gear.length} chargés',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: packed == gear.length ? const Color(0xFF2E7D32) : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
      ]),
      if (gear.isNotEmpty) ...[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: packed / gear.length,
            color: packed == gear.length ? const Color(0xFF2E9E6A) : AppColors.gold,
            backgroundColor: AppColors.aubergine.withValues(alpha: 0.08),
          ),
        ),
      ],
      const SizedBox(height: 8),
      if (gear.isNotEmpty)
        Card(
          child: Column(children: [
            for (final g in gear)
              CheckboxListTile(
                value: g.packed,
                onChanged: widget.canEdit ? (_) => _toggle(g) : null,
                secondary: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 44, height: 44, child: StoredPhoto(_item(g.equipmentId)!.photoPath)),
                ),
                title: Text(_item(g.equipmentId)!.name,
                    style: g.packed
                        ? TextStyle(decoration: TextDecoration.lineThrough, color: theme.colorScheme.onSurfaceVariant)
                        : null),
                subtitle: Text('× ${g.quantity}'),
              ),
          ]),
        ),
      if (widget.canEdit)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: Icon(gear.isEmpty ? Icons.add_rounded : Icons.edit_note_rounded),
            label: Text(gear.isEmpty ? 'Choisir le matériel dans l\'inventaire' : 'Modifier la liste'),
            onPressed: _items.isEmpty
                ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('L\'inventaire est vide : ajoute d\'abord le matériel dans l\'onglet Inventaire.')))
                : _choose,
          ),
        ),
    ]);
  }
}

/// Choix du matériel dans l'inventaire, avec la quantité à emporter.
class _GearPicker extends StatefulWidget {
  final List<EquipmentItem> items;
  final List<EquipmentCategory> categories;
  final Map<String, int> initial;

  const _GearPicker({required this.items, required this.categories, required this.initial});

  @override
  State<_GearPicker> createState() => _GearPickerState();
}

class _GearPickerState extends State<_GearPicker> {
  late final Map<String, int> _picked = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final shown = widget.items.where((i) => q.isEmpty || i.name.toLowerCase().contains(q)).toList();
    final groups = <String, List<EquipmentItem>>{};
    for (final i in shown) {
      final name = widget.categories.where((c) => c.id == i.categoryId).firstOrNull?.name ?? 'Sans catégorie';
      groups.putIfAbsent(name, () => []).add(i);
    }
    final names = groups.keys.toList()..sort((a, b) => a == 'Sans catégorie' ? 1 : (b == 'Sans catégorie' ? -1 : a.compareTo(b)));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matériel'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _picked),
              child: Text(_picked.isEmpty ? 'Valider' : 'Valider (${_picked.length})'),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Rechercher'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        for (final name in names) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(name, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.tertiary)),
          ),
          for (final i in groups[name]!)
            ListTile(
              leading: Checkbox(
                value: _picked.containsKey(i.id),
                onChanged: (v) => setState(() => v == true ? _picked[i.id] = 1 : _picked.remove(i.id)),
              ),
              title: Text(i.name),
              subtitle: Text('${i.quantity} dans le local'),
              onTap: () => setState(() => _picked.containsKey(i.id) ? _picked.remove(i.id) : _picked[i.id] = 1),
              trailing: _picked.containsKey(i.id)
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                        onPressed: _picked[i.id]! > 1 ? () => setState(() => _picked[i.id] = _picked[i.id]! - 1) : null,
                      ),
                      Text('${_picked[i.id]}', style: theme.textTheme.titleMedium),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        onPressed: _picked[i.id]! < i.quantity || i.quantity == 0
                            ? () => setState(() => _picked[i.id] = _picked[i.id]! + 1)
                            : null,
                      ),
                    ])
                  : SizedBox(width: 44, height: 44, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: StoredPhoto(i.photoPath))),
            ),
        ],
      ]),
    );
  }
}
