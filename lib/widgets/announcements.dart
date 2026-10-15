import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/agenda.dart';
import '../services/errors.dart';
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

  /// Écrire une annonce et choisir combien de temps elle reste sur l'accueil.
  Future<void> write() async {
    final controller = TextEditingController();
    var choice = _durations[2];
    DateTime? until;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) {
        final end = choice.$2 == null ? until : DateTime.now().add(choice.$2!);
        return AlertDialog(
          title: const Text('Nouvelle annonce'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Ex. Samedi la répétition a lieu au Hangar.'),
                ),
                const SizedBox(height: 16),
                Text('Reste sur l\'accueil', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final d in _durations)
                    ChoiceChip(
                      label: Text(d.$1),
                      selected: choice == d,
                      onSelected: (_) => setDialog(() => choice = d),
                    ),
                  ChoiceChip(
                    label: Text(choice.$1 == _untilLabel && until != null
                        ? 'Jusqu\'au ${DateFormat('d MMM', 'fr_FR').format(until!)}'
                        : 'Jusqu\'à une date…'),
                    selected: choice.$1 == _untilLabel,
                    onSelected: (_) async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        locale: const Locale('fr', 'FR'),
                        initialDate: until ?? now.add(const Duration(days: 7)),
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                      );
                      if (picked == null) return;
                      // Visible toute la journée choisie
                      setDialog(() {
                        until = DateTime(picked.year, picked.month, picked.day + 1);
                        choice = (_untilLabel, null);
                      });
                    },
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  end == null
                      ? (choice.$1 == _untilLabel ? 'Choisis la date.' : 'Reste affichée jusqu\'à ce que tu la retires.')
                      : 'Visible jusqu\'au ${DateFormat("EEEE d MMMM 'à' HH'h'mm", 'fr_FR').format(end)}.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: choice.$1 == _untilLabel && until == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Publier'),
            ),
          ],
        );
      }),
    );
    final body = controller.text.trim();
    if (ok != true || body.isEmpty) return;
    final expiresAt = choice.$1 == _untilLabel ? until : (choice.$2 == null ? null : DateTime.now().add(choice.$2!));
    await widget.backend.postAnnouncement(body, expiresAt: expiresAt);
    _load();
  }

  static const _untilLabel = 'date';
  static const List<(String, Duration?)> _durations = [
    ('1 jour', Duration(days: 1)),
    ('3 jours', Duration(days: 3)),
    ('1 semaine', Duration(days: 7)),
    ('2 semaines', Duration(days: 14)),
    ('1 mois', Duration(days: 30)),
    ('Sans fin', null),
  ];

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
    if (await attempt(() => widget.backend.deleteAnnouncement(a.id), what: 'Suppression impossible')) _load();
  }

  @override
  Widget build(BuildContext context) {
    // Seuls l'admin et le responsable gèrent les annonces ; les autres ne voient que celles publiées.
    final editor = widget.profile.canAnnounce;
    if (_items == null) return const SizedBox.shrink();
    // Seules les annonces encore en cours s'affichent sur l'accueil
    final items = _items!.where((a) => a.isActive()).toList();
    final theme = Theme.of(context);
    if (items.isEmpty) {
      // Les autres ne voient rien ; l'admin et le responsable peuvent en créer une.
      if (!editor) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionHeader('Annonce'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              leading: const Icon(Icons.campaign_rounded, color: Color(0xFFB8860B)),
              title: const Text('Aucune annonce en cours'),
              subtitle: const Text('Les membres ne voient cette partie que s\'il y a une annonce.'),
              trailing: FilledButton.tonal(onPressed: write, child: const Text('Créer')),
              onTap: write,
            ),
          ),
        ),
      ]);
    }
    // Accueil allégé : seulement la dernière annonce, les autres sur demande.
    final shown = _showAll ? items : items.take(1).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(items.length > 1 ? 'Annonces' : 'Annonce',
          actionLabel: editor ? 'Nouvelle' : null, onAction: write),
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
                    [
                      _names[a.authorId] ?? 'Référent',
                      DateFormat('d MMM, HH:mm', 'fr_FR').format(a.createdAt),
                      if (editor && a.expiresAt != null)
                        'affichée jusqu\'au ${DateFormat('d MMM', 'fr_FR').format(a.expiresAt!.subtract(const Duration(minutes: 1)))}',
                    ].join(' · '),
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
      if (items.length > 1 && !_showAll)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: () => setState(() => _showAll = true), child: Text('Voir les ${items.length} annonces')),
          ),
        ),
    ]);
  }
}
