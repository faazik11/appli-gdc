import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/event_widgets.dart';
import '../widgets/ui.dart';

/// Un taux : n sur total (total = 0 quand il n'y a encore rien à compter).
class Rate {
  final int n;
  final int total;

  const Rate(this.n, this.total);

  double? get value => total == 0 ? null : n / total;
  String get percent => total == 0 ? '—' : '${(n * 100 / total).round()} %';
}

/// Bilan d'un membre : présences notées à l'appel et réponses données.
class MemberStats {
  final Profile member;
  final Rate rehearsals;
  final Rate shows;
  final Rate responses;

  /// Événements passés dont l'appel a été fait, du plus récent au plus ancien.
  final List<(ChoirEvent, Participant?)> history;

  const MemberStats(this.member, this.rehearsals, this.shows, this.responses, this.history);

  factory MemberStats.compute(Profile m, List<ChoirEvent> events) {
    final checked = events.where((e) => !e.isUpcoming && e.rollCallDone).toList()
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    Rate rate(EventKind k) {
      final list = checked.where((e) => e.kind == k);
      return Rate(list.where((e) => e.participantOf(m.id)?.attended == true).length, list.length);
    }

    return MemberStats(
      m,
      rate(EventKind.repetition),
      rate(EventKind.prestation),
      Rate(events.where((e) => e.participantOf(m.id)?.response != null).length, events.length),
      [for (final e in checked) (e, e.participantOf(m.id))],
    );
  }
}

Color rateColor(double? r) => r == null
    ? Colors.grey
    : r >= 0.75
        ? const Color(0xFF2E9E6A)
        : r >= 0.5
            ? const Color(0xFFD08A1E)
            : const Color(0xFFC6464B);

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Rate rate;
  final String unit;

  const _StatTile(this.icon, this.label, this.rate, this.unit);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = rateColor(rate.value);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: theme.colorScheme.tertiary),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: theme.textTheme.labelLarge, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          Text(rate.percent, style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 30, height: 1, color: color)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate.value ?? 0,
              minHeight: 6,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(rate.total == 0 ? 'Pas encore de données' : '${rate.n} sur ${rate.total} $unit',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// Les trois taux et l'historique d'un membre.
class MemberStatsView extends StatelessWidget {
  final MemberStats stats;

  const MemberStatsView(this.stats, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final tiles = [
      _StatTile(Icons.music_note_rounded, 'Répétitions', stats.rehearsals, 'répétitions'),
      _StatTile(Icons.star_rounded, 'Prestations', stats.shows, 'prestations'),
      _StatTile(Icons.forum_rounded, 'Réponses', stats.responses, 'événements'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: wide
            ? Row(children: [for (final t in tiles) Expanded(child: t)])
            : Column(children: [
                Row(children: [Expanded(child: tiles[0]), Expanded(child: tiles[1])]),
                tiles[2],
              ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
        child: Text(
          'Présences d\'après l\'appel du chef de chœur. Réponses : événements où « Présent », « Peut-être » ou « Absent » a été indiqué.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
      const SectionHeader('Historique'),
      if (stats.history.isEmpty)
        const EmptyState(
          icon: Icons.history_rounded,
          title: 'Aucun appel pour l\'instant',
          message: 'Les répétitions et prestations où l\'appel a été fait apparaîtront ici.',
        )
      else
        for (final (e, p) in stats.history)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Card(
              child: ListTile(
                leading: Icon(kindIcon(e.kind), color: kindColor(e.kind)),
                title: Text(e.displayTitle),
                subtitle: Text('${formatDay(e.startsAt)}${_said(p?.response)}'),
                trailing: _PresenceChip(p?.attended == true),
              ),
            ),
          ),
    ]);
  }

  static String _said(EventResponse? r) => switch (r) {
        EventResponse.present => ' · avait dit présent',
        EventResponse.peutEtre => ' · avait dit peut-être',
        EventResponse.absent => ' · avait prévenu',
        null => ' · pas de réponse',
      };
}

class _PresenceChip extends StatelessWidget {
  final bool present;

  const _PresenceChip(this.present);

  @override
  Widget build(BuildContext context) {
    final color = present ? const Color(0xFF2E9E6A) : const Color(0xFFC6464B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(present ? 'Présent' : 'Absent',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// Fiche d'un membre, ouverte par un chef ou l'admin.
class MemberAttendanceScreen extends StatelessWidget {
  final MemberStats stats;

  const MemberAttendanceScreen(this.stats, {super.key});

  @override
  Widget build(BuildContext context) {
    final name = stats.member.fullName.isEmpty ? 'Sans nom' : stats.member.fullName;
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 40), children: [
        ContentWidth(maxWidth: 800, child: MemberStatsView(stats)),
      ]),
    );
  }
}

/// Vue d'ensemble pour les chefs et l'admin : un membre par ligne avec ses trois taux.
class AttendanceOverview extends StatelessWidget {
  final List<MemberStats> stats;

  const AttendanceOverview(this.stats, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    double avg(Rate Function(MemberStats) f) {
      final values = stats.map((s) => f(s).value).whereType<double>().toList();
      return values.isEmpty ? -1 : values.reduce((a, b) => a + b) / values.length;
    }

    String pct(double v) => v < 0 ? '—' : '${(v * 100).round()} %';
    final sorted = [...stats]..sort((a, b) => (b.rehearsals.value ?? -1).compareTo(a.rehearsals.value ?? -1));
    Widget groupStat(String label, double v) => Expanded(
          child: Column(children: [
            Text(pct(v), style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 28, color: AppColors.goldLight)),
            Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white)),
          ]),
        );
    Widget mini(String label, Rate r) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(r.percent, style: theme.textTheme.titleSmall?.copyWith(color: rateColor(r.value))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: Card(
          color: AppColors.aubergine,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: Column(children: [
              const Text('Moyenne du groupe',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white70, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              Row(children: [
                groupStat('Répétitions', avg((s) => s.rehearsals)),
                groupStat('Prestations', avg((s) => s.shows)),
                groupStat('Réponses', avg((s) => s.responses)),
              ]),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
        child: Text('Touche un membre pour voir sa fiche et son historique.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
      for (final s in sorted)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemberAttendanceScreen(s))),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(children: [
                  Avatar(s.member.fullName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.member.fullName.isEmpty ? 'Sans nom' : s.member.fullName, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Row(children: [
                        mini('Répétitions', s.rehearsals),
                        mini('Prestations', s.shows),
                        mini('Réponses', s.responses),
                      ]),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}
