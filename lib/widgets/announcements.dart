import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/agenda.dart';
import '../theme.dart';
import 'ui.dart';

/// Annonces du chef de chœur en haut de l'accueil.
class AnnouncementsSection extends StatefulWidget {
  final Profile profile;
  final AgendaBackend backend;

  const AnnouncementsSection({super.key, required this.profile, required this.backend});

  @override
  State<AnnouncementsSection> createState() => AnnouncementsSectionState();
}

class AnnouncementsSectionState extends State<AnnouncementsSection> {
  List<Announcement>? _items;
  Map<String, String> _names = const {};
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([widget.backend.announcements(), widget.backend.members()]);
      if (!mounted) return;
      setState(() {
        _items = r[0] as List<Announcement>;
        _names = {for (final p in r[1] as List<Profile>) p.id: p.fullName};
      });
    } catch (_) {
      // L'accueil reste utilisable sans les annonces.
    }
  }

  /// Écrire une annonce (aussi accessible depuis les raccourcis de l'accueil).
  Future<void> write() async {
    final controller = TextEditingController();
    final body = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle annonce'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Ex. Samedi la répétition a lieu au Hangar.'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Publier')),
        ],
      ),
    );
    if (body == null || body.isEmpty) return;
    await widget.backend.postAnnouncement(body);
    _load();
  }

  Future<void> _delete(Announcement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Supprimer cette annonce ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.backend.deleteAnnouncement(a.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final editor = widget.profile.isEditor;
    // Accueil allégé : seulement la dernière annonce, les autres sur demande.
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final shown = _showAll ? items : items.take(1).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('Annonce',
          actionLabel: items.length > 1 && !_showAll ? 'Voir les ${items.length}' : null,
          onAction: () => setState(() => _showAll = true)),
      for (final a in shown)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardTheme.color ?? theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border(left: BorderSide(color: AppColors.gold, width: 4)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.campaign_rounded, color: Color(0xFFB8860B)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.body, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text(
                    '${_names[a.authorId] ?? 'Chef de chœur'} · ${DateFormat('d MMM, HH:mm', 'fr_FR').format(a.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
              if (editor)
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => _delete(a),
                ),
            ]),
          ),
        ),
      if (editor && items.length > 2 && !_showAll)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => setState(() => _showAll = true), child: Text('Voir les ${items.length} annonces')),
          ),
        ),
    ]);
  }
}
