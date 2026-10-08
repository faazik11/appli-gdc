import 'package:flutter/material.dart';

import '../models.dart';
import '../services/agenda.dart';
import '../theme.dart';
import '../widgets/event_widgets.dart';
import '../widgets/ui.dart';
import 'event_form_screen.dart';
import 'event_screen.dart';

class AgendaData {
  final List<ChoirEvent> events;
  final List<Profile> members;

  const AgendaData(this.events, this.members);

  List<ChoirEvent> get upcoming => events.where((e) => e.isUpcoming).toList();
  List<ChoirEvent> get past => events.where((e) => !e.isUpcoming).toList().reversed.toList();

  static Future<AgendaData> load(AgendaBackend backend) async {
    final r = await Future.wait([backend.events(), backend.members()]);
    return AgendaData(r[0] as List<ChoirEvent>, r[1] as List<Profile>);
  }
}

/// Ouvre le détail d'un événement ; renvoie true si quelque chose a changé.
Future<bool> openEvent(BuildContext context, AgendaBackend backend, Profile profile, ChoirEvent e, AgendaData data) async {
  final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => EventScreen(
      backend: backend,
      event: e,
      profile: profile,
      members: data.members,
      locations: knownLocations(data.events),
    ),
  ));
  return changed == true;
}

enum _View { upcoming, past, attendance }

/// Onglet Agenda : répétitions et prestations à venir, passées, et suivi des présences.
class AgendaPanel extends StatefulWidget {
  final Profile profile;
  final AgendaBackend backend;

  const AgendaPanel({super.key, required this.profile, required this.backend});

  @override
  State<AgendaPanel> createState() => _AgendaPanelState();
}

class _AgendaPanelState extends State<AgendaPanel> {
  AgendaData? _data;
  String? _error;
  _View _view = _View.upcoming;
  EventKind _statsKind = EventKind.repetition;

  bool get _canEdit => widget.profile.isEditor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await AgendaData.load(widget.backend);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Impossible de charger l\'agenda : $e');
    }
  }

  Future<void> _respond(ChoirEvent e, EventResponse r) async {
    try {
      await widget.backend.setResponse(e.id, widget.profile.id, r);
      await _load();
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Réponse non enregistrée : $err')));
    }
  }

  Future<void> _push(Widget screen) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (saved == true) _load();
  }

  void _newSheet() {
    final data = _data!;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) {
        Widget tile(IconData icon, Color color, String title, String subtitle, Widget screen) => ListTile(
              leading: CircleAvatar(backgroundColor: color, foregroundColor: Colors.white, child: Icon(icon)),
              title: Text(title),
              subtitle: Text(subtitle),
              onTap: () {
                Navigator.pop(sheet);
                _push(screen);
              },
            );
        final locations = knownLocations(data.events);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              tile(Icons.date_range_rounded, AppColors.aubergine, 'Programme de la semaine',
                  'Les répétitions habituelles, horaires et lieu à ajuster',
                  WeekPlannerScreen(backend: widget.backend, events: data.events)),
              tile(Icons.music_note_rounded, AppColors.aubergineLight, 'Une répétition',
                  'Une répétition en plus, à la date de ton choix',
                  EventFormScreen(backend: widget.backend, kind: EventKind.repetition, locations: locations)),
              tile(Icons.star_rounded, const Color(0xFFB8860B), 'Une prestation', 'Concert, mariage, fête…',
                  EventFormScreen(backend: widget.backend, kind: EventKind.prestation, locations: locations)),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;
    Widget body;
    if (_error != null) {
      body = EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Connexion impossible',
        message: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Réessayer')),
      );
    } else if (data == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
          ContentWidth(
            maxWidth: 800,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Text('Agenda', style: theme.textTheme.headlineLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Text('Répétitions et prestations du groupe',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SegmentedButton<_View>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: _View.upcoming, label: Text('À venir')),
                    const ButtonSegment(value: _View.past, label: Text('Passés')),
                    if (_canEdit) const ButtonSegment(value: _View.attendance, label: Text('Présences')),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
              ),
              const SizedBox(height: 14),
              ...switch (_view) {
                _View.upcoming => _eventList(data, data.upcoming, upcoming: true),
                _View.past => _eventList(data, data.past, upcoming: false),
                _View.attendance => _attendance(data, theme),
              },
            ]),
          ),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _canEdit && data != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Programmer'),
              onPressed: _newSheet,
            )
          : null,
      body: body,
    );
  }

  List<Widget> _eventList(AgendaData data, List<ChoirEvent> events, {required bool upcoming}) {
    if (events.isEmpty) {
      return [
        EmptyState(
          icon: upcoming ? Icons.event_available_rounded : Icons.history_rounded,
          title: upcoming ? 'Rien de prévu pour l\'instant' : 'Aucun événement passé',
          message: upcoming
              ? (_canEdit
                  ? 'Programme la semaine : les membres verront la prochaine répétition et pourront répondre.'
                  : 'Les prochaines répétitions et prestations apparaîtront ici.')
              : 'L\'historique des répétitions et prestations s\'affichera ici.',
          action: upcoming && _canEdit
              ? FilledButton.icon(
                  icon: const Icon(Icons.date_range_rounded),
                  label: const Text('Programmer la semaine'),
                  onPressed: () => _push(WeekPlannerScreen(backend: widget.backend, events: data.events)),
                )
              : null,
        ),
      ];
    }
    return [
      for (final e in events)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: EventCard(
            event: e,
            myId: widget.profile.id,
            onTap: () async {
              if (await openEvent(context, widget.backend, widget.profile, e, data)) _load();
            },
            onRespond: upcoming ? (r) => _respond(e, r) : null,
          ),
        ),
    ];
  }

  List<Widget> _attendance(AgendaData data, ThemeData theme) {
    final done = data.past.where((e) => e.kind == _statsKind && e.rollCallDone).toList();
    final rows = [
      for (final m in data.members)
        (m, done.where((e) => e.participantOf(m.id)?.attended == true).length),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final average = rows.isEmpty || done.isEmpty
        ? 0.0
        : rows.fold<int>(0, (n, r) => n + r.$2) / (rows.length * done.length);
    final notDone = data.past.where((e) => e.kind == _statsKind && !e.rollCallDone).length;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(spacing: 8, children: [
          for (final k in EventKind.values)
            ChoiceChip(
              label: Text(k == EventKind.repetition ? 'Répétitions' : 'Prestations'),
              selected: _statsKind == k,
              onSelected: (_) => setState(() => _statsKind = k),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Card(
          color: AppColors.aubergine,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${(average * 100).round()} %',
                      style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 34, color: AppColors.goldLight)),
                  Text('de présence en moyenne sur ${done.length} ${_statsKind == EventKind.repetition ? 'répétition(s)' : 'prestation(s)'}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white)),
                ]),
              ),
              const Icon(Icons.insights_rounded, color: AppColors.goldLight, size: 40),
            ]),
          ),
        ),
      ),
      if (notDone > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 6),
          child: Text('$notDone événement(s) passé(s) sans appel : ouvre-les dans « Passés » pour noter les présents.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      if (done.isEmpty)
        const EmptyState(
          icon: Icons.how_to_reg_rounded,
          title: 'Pas encore d\'appel',
          message: 'Après une répétition, ouvre-la et utilise « Faire l\'appel ». Les statistiques apparaîtront ici.',
        )
      else
        for (final (m, n) in rows)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 16, 12),
                child: Row(children: [
                  Avatar(m.fullName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(m.fullName.isEmpty ? 'Sans nom' : m.fullName, style: theme.textTheme.titleSmall)),
                        Text('$n / ${done.length}', style: theme.textTheme.labelLarge),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: n / done.length,
                          minHeight: 7,
                          color: _rateColor(n / done.length),
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
    ];
  }
}

Color _rateColor(double r) => r >= 0.75
    ? const Color(0xFF2E9E6A)
    : r >= 0.5
        ? const Color(0xFFD08A1E)
        : const Color(0xFFC6464B);

/// Carte d'accueil : la prochaine répétition (et la prochaine prestation) avec réponse rapide.
class NextEventsSection extends StatefulWidget {
  final Profile profile;
  final AgendaBackend backend;
  final VoidCallback onOpenAgenda;

  const NextEventsSection({super.key, required this.profile, required this.backend, required this.onOpenAgenda});

  @override
  State<NextEventsSection> createState() => _NextEventsSectionState();
}

class _NextEventsSectionState extends State<NextEventsSection> {
  AgendaData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await AgendaData.load(widget.backend);
      if (mounted) setState(() => _data = d);
    } catch (_) {
      // L'accueil reste utilisable même si l'agenda ne charge pas.
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final upcoming = data.upcoming;
    final rehearsal = upcoming.where((e) => e.isRehearsal).firstOrNull;
    final show = upcoming.where((e) => !e.isRehearsal).firstOrNull;
    final items = [rehearsal, show].whereType<ChoirEvent>().toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(rehearsal == null ? 'Agenda' : 'Prochaine répétition',
          actionLabel: 'Agenda', onAction: widget.onOpenAgenda),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.event_busy_rounded),
              title: const Text('Aucune répétition programmée'),
              subtitle: Text(widget.profile.isEditor ? 'Programme la semaine depuis l\'agenda' : 'Elle apparaîtra ici dès qu\'elle sera fixée'),
              onTap: widget.onOpenAgenda,
            ),
          ),
        ),
      for (final e in items)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: EventCard(
            event: e,
            myId: widget.profile.id,
            onTap: () async {
              if (await openEvent(context, widget.backend, widget.profile, e, data)) _load();
            },
            onRespond: (r) async {
              await widget.backend.setResponse(e.id, widget.profile.id, r);
              _load();
            },
          ),
        ),
    ]);
  }
}
