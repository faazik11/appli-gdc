import 'package:flutter/material.dart';

import '../models.dart';
import '../services/agenda.dart';
import '../widgets/event_widgets.dart';
import '../widgets/library_links.dart';
import '../widgets/ui.dart';

DateTime _at(DateTime day, TimeOfDay t) => DateTime(day.year, day.month, day.day, t.hour, t.minute);

String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}h${t.minute.toString().padLeft(2, '0')}';

/// Lieux déjà utilisés, du plus récent au plus ancien.
List<String> knownLocations(List<ChoirEvent> events) {
  final seen = <String>{};
  for (final e in [...events]..sort((a, b) => b.startsAt.compareTo(a.startsAt))) {
    if (e.location != null) seen.add(e.location!);
  }
  return seen.toList();
}

/// Champ lieu avec suggestions des lieux déjà utilisés.
class LocationField extends StatefulWidget {
  final TextEditingController controller;
  final List<String> suggestions;

  const LocationField({super.key, required this.controller, required this.suggestions});

  @override
  State<LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<LocationField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (v) => widget.suggestions.where((s) => s.toLowerCase().contains(v.text.toLowerCase()) && s != v.text),
      fieldViewBuilder: (context, c, focus, _) => TextField(
        controller: c,
        focusNode: focus,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Lieu', prefixIcon: Icon(Icons.place_rounded)),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 500),
            child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
              for (final o in options)
                ListTile(leading: const Icon(Icons.history_rounded), title: Text(o), onTap: () => onSelected(o)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Création ou modification d'une répétition ou d'une prestation.
class EventFormScreen extends StatefulWidget {
  final AgendaBackend backend;
  final EventKind kind;
  final ChoirEvent? event;
  final List<String> locations;
  final LibraryLinks? links;

  const EventFormScreen(
      {super.key, required this.backend, required this.kind, this.event, this.locations = const [], this.links});

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  late EventKind _kind = widget.event?.kind ?? widget.kind;
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _location = TextEditingController(
      text: widget.event?.location ??
          (widget.kind == EventKind.repetition && widget.locations.isNotEmpty ? widget.locations.first : ''));
  late final _notes = TextEditingController(text: widget.event?.notes ?? '');
  late DateTime _day = widget.event?.startsAt ?? DateTime.now().add(const Duration(days: 1));
  late TimeOfDay _start = widget.event == null
      ? (_kind == EventKind.repetition ? const TimeOfDay(hour: 20, minute: 0) : const TimeOfDay(hour: 18, minute: 0))
      : TimeOfDay.fromDateTime(widget.event!.startsAt);
  late TimeOfDay? _end = widget.event?.endsAt == null ? null : TimeOfDay.fromDateTime(widget.event!.endsAt!);
  late final List<String> _songIds = [...?widget.event?.songIds];
  late String? _bookletId = widget.event?.bookletId;
  bool _saving = false;

  LibraryLinks get _links => widget.links ?? LibraryLinks.empty;

  Future<void> _pickSongs() async {
    final ids = await pickSongs(context, _links, _songIds);
    if (ids != null) {
      setState(() => _songIds
        ..clear()
        ..addAll(ids));
    }
  }

  Widget _songsSection(ThemeData theme) {
    final rehearsal = _kind == EventKind.repetition;
    final songs = _songIds.map(_links.song).whereType<Song>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 18),
      Text(rehearsal ? 'Chants à travailler' : 'Programme', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      if (!rehearsal) ...[
        DropdownButtonFormField<String?>(
          initialValue: _links.booklet(_bookletId)?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Livret de la prestation', prefixIcon: Icon(Icons.menu_book_rounded)),
          items: [
            const DropdownMenuItem(value: null, child: Text('Aucun livret')),
            for (final b in _links.booklets) DropdownMenuItem(value: b.id, child: Text(b.title, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _bookletId = v),
        ),
        const SizedBox(height: 8),
        if (_bookletId != null && songs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Le programme reprend les chants du livret.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
      ],
      if (songs.isNotEmpty)
        Card(
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => setState(() => _songIds.insert(to, _songIds.removeAt(from))),
            children: [
              for (final (i, s) in songs.indexed)
                ListTile(
                  key: ValueKey(s.id),
                  dense: true,
                  leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator_rounded)),
                  title: Text(s.title),
                  trailing: IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _songIds.remove(s.id)),
                  ),
                ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.queue_music_rounded),
          label: Text(songs.isEmpty ? 'Choisir des chants' : 'Modifier la liste'),
          onPressed: _pickSongs,
        ),
      ),
    ]);
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d != null) setState(() => _day = d);
  }

  Future<void> _pickTime(bool start) async {
    final t = await showTimePicker(context: context, initialTime: start ? _start : (_end ?? _start));
    if (t != null) setState(() => start ? _start = t : _end = t);
  }

  Future<void> _save() async {
    if (_kind == EventKind.prestation && _title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Donne un nom à la prestation')));
      return;
    }
    setState(() => _saving = true);
    try {
      final startsAt = _at(_day, _start);
      var endsAt = _end == null ? null : _at(_day, _end!);
      if (endsAt != null && !endsAt.isAfter(startsAt)) endsAt = endsAt.add(const Duration(days: 1));
      await widget.backend.saveEvent(
        id: widget.event?.id,
        kind: _kind,
        title: _title.text,
        startsAt: startsAt,
        endsAt: endsAt,
        location: _location.text,
        notes: _notes.text,
        songIds: _songIds,
        bookletId: _kind == EventKind.prestation ? _bookletId : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.event != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Modifier' : (_kind == EventKind.repetition ? 'Nouvelle répétition' : 'Nouvelle prestation')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 100), children: [
        ContentWidth(
          maxWidth: 640,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<EventKind>(
                segments: [
                  for (final k in EventKind.values)
                    ButtonSegment(value: k, label: Text(kindLabel(k)), icon: Icon(kindIcon(k))),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _kind == EventKind.prestation ? 'Nom de la prestation' : 'Titre (facultatif)',
                  hintText: _kind == EventKind.prestation ? 'Ex. Mariage de Sarah et Karim' : 'Ex. Répétition générale',
                  prefixIcon: Icon(kindIcon(_kind)),
                ),
              ),
              const SizedBox(height: 18),
              Text('Quand', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.event_rounded),
                    title: Text(formatDay(_day)),
                    trailing: const Icon(Icons.edit_calendar_rounded),
                    onTap: _pickDay,
                  ),
                  const Divider(height: 1),
                  Row(children: [
                    Expanded(
                      child: ListTile(
                        leading: const Icon(Icons.schedule_rounded),
                        title: const Text('Début'),
                        subtitle: Text(_fmtTime(_start)),
                        onTap: () => _pickTime(true),
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        title: const Text('Fin'),
                        subtitle: Text(_end == null ? 'Facultatif' : _fmtTime(_end!)),
                        trailing: _end == null
                            ? null
                            : IconButton(
                                tooltip: 'Retirer l\'heure de fin',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => setState(() => _end = null),
                              ),
                        onTap: () => _pickTime(false),
                      ),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 18),
              LocationField(controller: _location, suggestions: widget.locations),
              _songsSection(theme),
              const SizedBox(height: 14),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Infos pour les membres',
                  hintText: 'Tenue, chants à revoir, parking…',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_rounded),
                label: Text(editing ? 'Enregistrer' : 'Ajouter à l\'agenda'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Programme de la semaine : les répétitions habituelles, horaires et lieu ajustables.
class WeekPlannerScreen extends StatefulWidget {
  final AgendaBackend backend;
  final List<ChoirEvent> events;

  const WeekPlannerScreen({super.key, required this.backend, required this.events});

  @override
  State<WeekPlannerScreen> createState() => _WeekPlannerScreenState();
}

class _Slot {
  bool enabled = true;
  int weekday;
  TimeOfDay start;
  TimeOfDay? end;

  _Slot(this.weekday, this.start, [this.end]);
}

class _WeekPlannerScreenState extends State<WeekPlannerScreen> {
  static const _days = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
  late DateTime _monday;
  late final List<_Slot> _slots;
  late final _location = TextEditingController(
      text: widget.events.where((e) => e.isRehearsal && e.location != null).lastOrNull?.location ?? '');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final thisMonday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    // Semaine en cours si elle n'a pas encore de répétition prévue, sinon la suivante.
    _monday = _rehearsalsIn(thisMonday).isEmpty ? thisMonday : thisMonday.add(const Duration(days: 7));
    while (_rehearsalsIn(_monday).isNotEmpty) {
      _monday = _monday.add(const Duration(days: 7));
    }
    _slots = _defaultSlots();
  }

  List<ChoirEvent> _rehearsalsIn(DateTime monday) => widget.events
      .where((e) => e.isRehearsal && !e.startsAt.isBefore(monday) && e.startsAt.isBefore(monday.add(const Duration(days: 7))))
      .toList();

  /// Mercredi soir et samedi après-midi, aux horaires utilisés la dernière fois.
  List<_Slot> _defaultSlots() {
    _Slot slot(int weekday, TimeOfDay start, TimeOfDay end) {
      final last = widget.events.where((e) => e.isRehearsal && e.startsAt.weekday == weekday).lastOrNull;
      if (last == null) return _Slot(weekday, start, end);
      return _Slot(weekday, TimeOfDay.fromDateTime(last.startsAt),
          last.endsAt == null ? null : TimeOfDay.fromDateTime(last.endsAt!));
    }

    return [
      slot(DateTime.wednesday, const TimeOfDay(hour: 20, minute: 0), const TimeOfDay(hour: 22, minute: 0)),
      slot(DateTime.saturday, const TimeOfDay(hour: 14, minute: 30), const TimeOfDay(hour: 17, minute: 0)),
    ];
  }

  DateTime _dayOf(_Slot s) => _monday.add(Duration(days: s.weekday - 1));

  Future<void> _save() async {
    final chosen = _slots.where((s) => s.enabled).toList();
    if (chosen.isEmpty) return;
    setState(() => _saving = true);
    try {
      for (final s in chosen) {
        final start = _at(_dayOf(s), s.start);
        var end = s.end == null ? null : _at(_dayOf(s), s.end!);
        if (end != null && !end.isAfter(start)) end = end.add(const Duration(days: 1));
        await widget.backend.saveEvent(kind: EventKind.repetition, startsAt: start, endsAt: end, location: _location.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sunday = _monday.add(const Duration(days: 6));
    final existing = _rehearsalsIn(_monday);
    return Scaffold(
      appBar: AppBar(title: const Text('Programme de la semaine')),
      body: ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 100), children: [
        ContentWidth(
          maxWidth: 640,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Card(
                child: Row(children: [
                  IconButton(
                    tooltip: 'Semaine précédente',
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => setState(() => _monday = _monday.subtract(const Duration(days: 7))),
                  ),
                  Expanded(
                    child: Column(children: [
                      Text('Semaine du', style: theme.textTheme.labelMedium),
                      Text('${_monday.day} au ${formatDay(sunday).split(' ').skip(1).join(' ')}',
                          textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Semaine suivante',
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => setState(() => _monday = _monday.add(const Duration(days: 7))),
                  ),
                ]),
              ),
              if (existing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Déjà prévu cette semaine : ${existing.map((e) => '${formatDay(e.startsAt).split(' ').first.toLowerCase()} ${formatTime(e.startsAt)}').join(', ')}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Répétitions', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final s in _slots)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                    child: Row(children: [
                      Checkbox(value: s.enabled, onChanged: (v) => setState(() => s.enabled = v ?? false)),
                      Expanded(
                        child: DropdownButton<int>(
                          value: s.weekday,
                          isExpanded: true,
                          underline: const SizedBox(),
                          items: [
                            for (var i = 1; i <= 7; i++)
                              DropdownMenuItem(
                                value: i,
                                child: Text('${_days[i - 1]} ${_monday.add(Duration(days: i - 1)).day}'),
                              ),
                          ],
                          onChanged: s.enabled ? (v) => setState(() => s.weekday = v!) : null,
                        ),
                      ),
                      TextButton(
                        onPressed: !s.enabled
                            ? null
                            : () async {
                                final t = await showTimePicker(context: context, initialTime: s.start);
                                if (t != null) setState(() => s.start = t);
                              },
                        child: Text(_fmtTime(s.start)),
                      ),
                      const Text('–'),
                      TextButton(
                        onPressed: !s.enabled
                            ? null
                            : () async {
                                final t = await showTimePicker(context: context, initialTime: s.end ?? s.start);
                                if (t != null) setState(() => s.end = t);
                              },
                        child: Text(s.end == null ? '…' : _fmtTime(s.end!)),
                      ),
                    ]),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Ajouter une répétition'),
                  onPressed: () => setState(() => _slots.add(_Slot(DateTime.friday, const TimeOfDay(hour: 20, minute: 0)))),
                ),
              ),
              const SizedBox(height: 12),
              LocationField(controller: _location, suggestions: knownLocations(widget.events)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving || !_slots.any((s) => s.enabled) ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.event_available_rounded),
                label: Text('Publier ${_slots.where((s) => s.enabled).length} répétition(s)'),
              ),
              const SizedBox(height: 8),
              Text('Les membres verront aussitôt la prochaine répétition sur leur accueil.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      ]),
    );
  }
}
