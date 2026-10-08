import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../theme.dart';

String formatTime(DateTime d) => DateFormat("HH'h'mm", 'fr_FR').format(d);

String formatDay(DateTime d) {
  final s = DateFormat('EEEE d MMMM', 'fr_FR').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

String formatHours(ChoirEvent e) =>
    e.endsAt == null ? formatTime(e.startsAt) : '${formatTime(e.startsAt)} – ${formatTime(e.endsAt!)}';

/// « Aujourd'hui », « Demain », « Dans 3 jours »…
String relativeDay(DateTime d) {
  final now = DateTime.now();
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  return switch (days) {
    0 => 'Aujourd\'hui',
    1 => 'Demain',
    < 0 => '',
    _ => 'Dans $days jours',
  };
}

Color kindColor(EventKind k) => k == EventKind.repetition ? AppColors.aubergineLight : const Color(0xFFB8860B);

String kindLabel(EventKind k) => k == EventKind.repetition ? 'Répétition' : 'Prestation';

IconData kindIcon(EventKind k) => k == EventKind.repetition ? Icons.music_note_rounded : Icons.star_rounded;

class KindBadge extends StatelessWidget {
  final EventKind kind;
  final bool onDark;

  const KindBadge(this.kind, {super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final color = onDark ? AppColors.goldLight : kindColor(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: onDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(kindIcon(kind), size: 13, color: color),
        const SizedBox(width: 4),
        Text(kindLabel(kind),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

/// Bloc date façon calendrier : jour de la semaine, numéro, mois.
class DateBlock extends StatelessWidget {
  final DateTime date;
  final EventKind kind;

  const DateBlock(this.date, this.kind, {super.key});

  @override
  Widget build(BuildContext context) {
    final rehearsal = kind == EventKind.repetition;
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: rehearsal
            ? AppColors.heroGradient
            : const LinearGradient(colors: [Color(0xFFE0B341), Color(0xFFB8860B)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(DateFormat('EEE', 'fr_FR').format(date).replaceAll('.', '').toUpperCase(),
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: rehearsal ? AppColors.goldLight : Colors.white)),
        Text('${date.day}',
            style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 26, height: 1.1, color: Colors.white)),
        Text(DateFormat('MMM', 'fr_FR').format(date).replaceAll('.', ''),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
      ]),
    );
  }
}

/// Les trois boutons de réponse d'un membre.
class ResponseButtons extends StatelessWidget {
  final EventResponse? current;
  final ValueChanged<EventResponse> onChanged;
  final bool compact;

  const ResponseButtons({super.key, required this.current, required this.onChanged, this.compact = false});

  static const options = [
    (EventResponse.present, 'Présent', Icons.check_circle_rounded, Color(0xFF2E9E6A)),
    (EventResponse.peutEtre, 'Peut-être', Icons.help_rounded, Color(0xFFD08A1E)),
    (EventResponse.absent, 'Absent', Icons.cancel_rounded, Color(0xFFC6464B)),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      for (final (value, label, icon, color) in options)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: current == value ? color : color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onChanged(value),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: compact ? 8 : 11),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, size: 17, color: current == value ? Colors.white : color),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: current == value ? Colors.white : scheme.onSurface,
                          )),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Résumé des réponses : 12 présents · 2 peut-être · 1 absent.
class ResponseCounts extends StatelessWidget {
  final ChoirEvent event;
  final bool labels;

  const ResponseCounts(this.event, {super.key, this.labels = false});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget item(IconData icon, Color color, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: muted)),
        ]);
    final done = event.rollCallDone;
    return Wrap(spacing: 12, runSpacing: 4, children: [
      if (done)
        item(Icons.how_to_reg_rounded, const Color(0xFF2E9E6A), '${event.attendedCount} présents à l\'appel')
      else ...[
        item(Icons.check_circle_rounded, const Color(0xFF2E9E6A), '${event.count(EventResponse.present)}${labels ? ' présent(s)' : ''}'),
        item(Icons.help_rounded, const Color(0xFFD08A1E), '${event.count(EventResponse.peutEtre)}${labels ? ' peut-être' : ''}'),
        item(Icons.cancel_rounded, const Color(0xFFC6464B), '${event.count(EventResponse.absent)}${labels ? ' absent(s)' : ''}'),
      ],
    ]);
  }
}

class EventCard extends StatelessWidget {
  final ChoirEvent event;
  final String myId;
  final VoidCallback onTap;
  final ValueChanged<EventResponse>? onRespond;

  const EventCard({super.key, required this.event, required this.myId, required this.onTap, this.onRespond});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final when = relativeDay(event.startsAt);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DateBlock(event.startsAt, event.kind),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    KindBadge(event.kind),
                    if (when.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(when,
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.tertiary)),
                    ],
                  ]),
                  const SizedBox(height: 6),
                  Text(event.displayTitle, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.schedule_rounded, size: 15, color: muted),
                    const SizedBox(width: 4),
                    Text(formatHours(event), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    if (event.location != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.place_rounded, size: 15, color: muted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(event.location!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 6),
                  ResponseCounts(event),
                ]),
              ),
            ]),
            if (onRespond != null) ...[
              const SizedBox(height: 12),
              ResponseButtons(compact: true, current: event.participantOf(myId)?.response, onChanged: onRespond!),
            ],
          ]),
        ),
      ),
    );
  }
}
