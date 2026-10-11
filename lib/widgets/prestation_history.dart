import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../theme.dart';
import 'event_widgets.dart';
import 'library_links.dart';
import 'ui.dart';

/// Historique des prestations : bilan, chants les plus chantés, puis chaque prestation
/// avec son lieu, le nombre de présents et les chants chantés.
class PrestationHistory extends StatelessWidget {
  /// Prestations passées, de la plus récente à la plus ancienne.
  final List<ChoirEvent> events;
  final LibraryLinks? links;
  final String myId;
  final void Function(ChoirEvent e) onOpen;

  const PrestationHistory({super.key, required this.events, required this.links, required this.myId, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (events.isEmpty) {
      return const EmptyState(
        icon: Icons.star_outline_rounded,
        title: 'Aucune prestation passée',
        message: 'Les prestations du groupe s\'afficheront ici une fois passées, avec les chants chantés.',
      );
    }
    final year = DateTime.now().year;
    final thisYear = events.where((e) => e.startsAt.year == year).length;
    final songsSung = <String, int>{};
    for (final e in events) {
      for (final s in links?.songsOf(e) ?? const <Song>[]) {
        songsSung[s.id] = (songsSung[s.id] ?? 0) + 1;
      }
    }
    final top = (songsSung.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).toList();
    final mine = events.where((e) => e.participantOf(myId)?.attended == true).length;
    final rollCalls = events.where((e) => e.rollCallDone).length;

    final byYear = <int, List<ChoirEvent>>{};
    for (final e in events) {
      byYear.putIfAbsent(e.startsAt.year, () => []).add(e);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Stat(value: '$thisYear', label: thisYear > 1 ? 'prestations en $year' : 'prestation en $year'),
          const SizedBox(width: 10),
          _Stat(value: '${songsSung.length}', label: songsSung.length > 1 ? 'chants différents' : 'chant chanté'),
          if (rollCalls > 0) ...[
            const SizedBox(width: 10),
            _Stat(value: '$mine/$rollCalls', label: 'où tu étais là'),
          ],
        ])),
      ),
      if (top.isNotEmpty) ...[
        const SectionHeader('Les plus chantés'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Column(children: [
              for (final (i, entry) in top.indexed)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: i == 0 ? AppColors.gold : AppColors.aubergine.withValues(alpha: 0.1),
                    foregroundColor: AppColors.aubergine,
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(links!.song(entry.key)!.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text('${entry.value} fois', style: theme.textTheme.bodySmall),
                  onTap: () => links!.openSong(links!.song(entry.key)!),
                ),
            ]),
          ),
        ),
      ],
      for (final y in byYear.keys) ...[
        SectionHeader('$y'),
        for (final e in byYear[y]!)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _PrestationCard(event: e, links: links, myId: myId, onTap: () => onOpen(e)),
          ),
      ],
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 26, color: Colors.white, height: 1.1)),
          const SizedBox(height: 2),
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.goldLight, fontFamily: 'Poppins'),
              maxLines: 2),
        ]),
      ),
    );
  }
}

class _PrestationCard extends StatelessWidget {
  final ChoirEvent event;
  final LibraryLinks? links;
  final String myId;
  final VoidCallback onTap;

  const _PrestationCard({required this.event, required this.links, required this.myId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final songs = links?.songsOf(event) ?? const <Song>[];
    final me = event.participantOf(myId)?.attended;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DateBlock(event.startsAt, event.kind),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(event.displayTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (event.location != null)
                    _Info(Icons.place_outlined, event.location!, muted),
                  if (event.rollCallDone)
                    _Info(Icons.groups_rounded, '${event.attendedCount} présents', muted),
                  if (me == true) _Info(Icons.check_circle_rounded, 'Tu y étais', const Color(0xFF2E7D32)),
                ]),
                if (songs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in songs)
                      Material(
                        color: AppColors.aubergine.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => links!.openSong(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(CategoryStyle.of(links!.categoryOf(s)?.name ?? '').icon,
                                  size: 14, color: AppColors.aubergine),
                              const SizedBox(width: 5),
                              Text(s.title, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.aubergine)),
                            ]),
                          ),
                        ),
                      ),
                  ]),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Chants non renseignés', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ),
                if (event.notes != null && event.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(event.notes!.trim(),
                      maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ],
                const SizedBox(height: 4),
                Text(DateFormat("EEEE d MMMM y · HH'h'mm", 'fr_FR').format(event.startsAt),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Info(this.icon, this.text, this.color);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color))),
      ]);
}
