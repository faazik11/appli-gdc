import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/agenda.dart';
import '../theme.dart';
import '../widgets/event_widgets.dart';
import '../widgets/ui.dart';
import 'event_form_screen.dart';

/// Détail d'un événement : infos, réponses des membres et appel (chefs et admins).
class EventScreen extends StatefulWidget {
  final AgendaBackend backend;
  final ChoirEvent event;
  final Profile profile;
  final List<Profile> members;
  final List<String> locations;

  const EventScreen({
    super.key,
    required this.backend,
    required this.event,
    required this.profile,
    required this.members,
    this.locations = const [],
  });

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  late ChoirEvent _event = widget.event;
  bool _changed = false;
  late bool _rollCall = widget.profile.isEditor && !_event.isUpcoming;

  bool get _canEdit => widget.profile.isEditor;

  Future<void> _refresh() async {
    final all = await widget.backend.events();
    final fresh = all.where((e) => e.id == _event.id).firstOrNull;
    if (!mounted) return;
    if (fresh == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _event = fresh);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _changed = true;
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action impossible : $e')));
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => EventFormScreen(backend: widget.backend, kind: _event.kind, event: _event, locations: widget.locations),
    ));
    if (saved == true) {
      _changed = true;
      _refresh();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('Supprimer « ${_event.displayTitle} » du ${formatDay(_event.startsAt).toLowerCase()} ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.backend.deleteEvent(_event.id);
    if (mounted) Navigator.pop(context, true);
  }

  void _openMap() {
    final q = Uri.encodeComponent(_event.location!);
    launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = _event.participantOf(widget.profile.id);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        body: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 210,
            foregroundColor: Colors.white,
            backgroundColor: AppColors.aubergine,
            actions: [
              if (_canEdit) ...[
                IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_rounded), onPressed: _edit),
                IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
              ],
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: _event.isRehearsal
                      ? AppColors.heroGradient
                      : const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.aubergine, Color(0xFF7A4A2A), Color(0xFFB8860B)]),
                ),
                child: SafeArea(
                  child: ContentWidth(
                    maxWidth: 800,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 56, 22, 20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                        KindBadge(_event.kind, onDark: true),
                        const SizedBox(height: 8),
                        Text(_event.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 30, height: 1.1, color: Colors.white)),
                        const SizedBox(height: 6),
                        Text('${formatDay(_event.startsAt)} · ${formatHours(_event)}',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: AppColors.goldLight.withValues(alpha: 0.95))),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ContentWidth(
              maxWidth: 800,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_event.location != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.place_rounded),
                        title: Text(_event.location!),
                        subtitle: const Text('Ouvrir dans le plan'),
                        trailing: const Icon(Icons.map_rounded),
                        onTap: _openMap,
                      ),
                    ),
                  if (_event.notes != null)
                    Card(
                      child: ListTile(leading: const Icon(Icons.notes_rounded), title: Text(_event.notes!)),
                    ),
                  if (_event.isUpcoming) ...[
                    const SizedBox(height: 12),
                    Text('Tu viens ?', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ResponseButtons(
                      current: me?.response,
                      onChanged: (r) => _run(() => widget.backend.setResponse(_event.id, widget.profile.id, r)),
                    ),
                  ],
                  if (_canEdit) ...[
                    const SizedBox(height: 20),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Réponses'), icon: Icon(Icons.forum_rounded)),
                        ButtonSegment(value: true, label: Text('Faire l\'appel'), icon: Icon(Icons.how_to_reg_rounded)),
                      ],
                      selected: {_rollCall},
                      onSelectionChanged: (s) => setState(() => _rollCall = s.first),
                    ),
                  ],
                  if (!_canEdit)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_event.isUpcoming ? 'Qui vient ?' : 'Bilan', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            ResponseCounts(_event, labels: true),
                          ]),
                        ),
                      ),
                    )
                  else if (_rollCall)
                    ..._rollCallList(theme)
                  else
                    ..._responseList(theme),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  String _name(String id) =>
      widget.members.where((m) => m.id == id).firstOrNull?.fullName ?? 'Ancien membre';

  List<Widget> _responseList(ThemeData theme) {
    final groups = [
      for (final (value, label, icon, color) in ResponseButtons.options)
        (label, icon, color, _event.participants.where((p) => p.response == value).map((p) => _name(p.profileId)).toList()),
      (
        'Sans réponse',
        Icons.hourglass_empty_rounded,
        theme.colorScheme.outline,
        widget.members
            .where((m) => _event.participantOf(m.id)?.response == null)
            .map((m) => m.fullName)
            .toList(),
      ),
    ];
    return [
      const SizedBox(height: 8),
      for (final (label, icon, color, names) in groups)
        if (names.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text('$label (${names.length})', style: theme.textTheme.titleSmall),
            ]),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final n in names..sort())
              Chip(avatar: Avatar(n, radius: 12), label: Text(n.isEmpty ? 'Sans nom' : n)),
          ]),
        ],
    ];
  }

  List<Widget> _rollCallList(ThemeData theme) {
    final present = widget.members.where((m) => _event.participantOf(m.id)?.attended == true).length;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text('$present présent(s) sur ${widget.members.length} membres',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
      for (final m in widget.members)
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 2, 8, 2),
            leading: Avatar(m.fullName),
            title: Text(m.fullName.isEmpty ? 'Sans nom' : m.fullName),
            subtitle: Text(switch (_event.participantOf(m.id)?.response) {
              EventResponse.present => 'Avait dit : présent',
              EventResponse.peutEtre => 'Avait dit : peut-être',
              EventResponse.absent => 'Avait dit : absent',
              null => 'Pas de réponse',
            }),
            trailing: _AttendanceToggle(
              value: _event.participantOf(m.id)?.attended,
              onChanged: (v) => _run(() => widget.backend.setAttended(_event.id, m.id, v)),
            ),
          ),
        ),
    ];
  }
}

class _AttendanceToggle extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?> onChanged;

  const _AttendanceToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget button(bool v, IconData icon, Color color, String tip) => IconButton(
          tooltip: tip,
          style: IconButton.styleFrom(
            backgroundColor: value == v ? color : color.withValues(alpha: 0.1),
            foregroundColor: value == v ? Colors.white : color,
          ),
          icon: Icon(icon),
          // Un second appui annule la saisie.
          onPressed: () => onChanged(value == v ? null : v),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      button(true, Icons.check_rounded, const Color(0xFF2E9E6A), 'Présent'),
      const SizedBox(width: 6),
      button(false, Icons.close_rounded, const Color(0xFFC6464B), 'Absent'),
    ]);
  }
}
