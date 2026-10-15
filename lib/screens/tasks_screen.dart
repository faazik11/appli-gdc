import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/agenda.dart';
import '../services/errors.dart';
import '../services/tasks.dart';
import '../theme.dart';
import '../widgets/event_widgets.dart';
import '../widgets/ui.dart';
import 'task_form_screen.dart';

const _doneColor = Color(0xFF2E7D32);
const _cantColor = Color(0xFFC62828);
const _lateColor = Color(0xFFD84315);

String statusLabel(TaskStatus s) => switch (s) {
      TaskStatus.aFaire => 'À faire',
      TaskStatus.fait => 'Fait',
      TaskStatus.impossible => 'Ne peut pas',
    };

Color statusColor(TaskStatus s) => switch (s) {
      TaskStatus.aFaire => AppColors.aubergineLight,
      TaskStatus.fait => _doneColor,
      TaskStatus.impossible => _cantColor,
    };

IconData statusIcon(TaskStatus s) => switch (s) {
      TaskStatus.aFaire => Icons.radio_button_unchecked_rounded,
      TaskStatus.fait => Icons.check_circle_rounded,
      TaskStatus.impossible => Icons.cancel_rounded,
    };

String dueLabel(DateTime d) {
  final rel = relativeDay(d);
  final day = DateFormat('EEE d MMM', 'fr_FR').format(d);
  return rel.isEmpty ? 'Pour le $day' : 'Pour le $day · $rel';
}

/// Liste des tâches : les siennes pour un membre, toutes (avec le suivi) pour le Responsable et les Référents.
class TasksScreen extends StatefulWidget {
  final Profile profile;
  final TasksBackend backend;
  final AgendaBackend agenda;

  const TasksScreen({super.key, required this.profile, required this.backend, required this.agenda});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<ChoirTask>? _tasks;
  List<Profile> _members = const [];
  String? _error;
  bool _showDone = false;
  bool _onlyMine = false;

  bool get _editor => widget.profile.isManager;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([widget.backend.tasks(), widget.agenda.members()]);
      if (!mounted) return;
      setState(() {
        _tasks = r[0] as List<ChoirTask>;
        _members = r[1] as List<Profile>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Impossible de charger les tâches : ${explain(e)}');
    }
  }

  Map<String, String> get _names => {for (final p in _members) p.id: p.fullName};

  Future<void> _open(ChoirTask t) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TaskScreen(
        profile: widget.profile,
        backend: widget.backend,
        agenda: widget.agenda,
        task: t,
        members: _members,
      ),
    ));
    _load();
  }

  Future<void> _create() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TaskFormScreen(backend: widget.backend, agenda: widget.agenda, members: _members),
    ));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.profile.id;
    final all = _tasks;
    Widget body;
    if (_error != null && all == null) {
      body = EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Connexion impossible',
        message: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Réessayer')),
      );
    } else if (all == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      // Un membre : « terminée » = il a répondu. Un éditeur : tout le monde a répondu.
      bool done(ChoirTask t) =>
          (_editor && !_onlyMine) ? t.isDone : (t.assignee(me)?.status ?? TaskStatus.aFaire) != TaskStatus.aFaire;
      final mine = (_editor && !_onlyMine) ? all : all.where((t) => t.assignee(me) != null).toList();
      final open = mine.where((t) => !done(t)).toList()
        ..sort((a, b) {
          // Les plus urgentes en premier, celles sans date à la fin
          if (a.dueDate == null && b.dueDate == null) return b.createdAt.compareTo(a.createdAt);
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
      final finished = mine.where(done).toList();
      final shown = _showDone ? finished : open;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
          ContentWidth(
            maxWidth: 760,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                    label: Text('En cours (${open.length})'),
                    selected: !_showDone,
                    onSelected: (_) => setState(() => _showDone = false),
                  ),
                  ChoiceChip(
                    label: Text('Terminées (${finished.length})'),
                    selected: _showDone,
                    onSelected: (_) => setState(() => _showDone = true),
                  ),
                  if (_editor)
                    FilterChip(
                      label: const Text('Seulement les miennes'),
                      selected: _onlyMine,
                      onSelected: (v) => setState(() => _onlyMine = v),
                    ),
                ]),
              ),
              if (shown.isEmpty)
                EmptyState(
                  icon: Icons.task_alt_rounded,
                  title: _showDone ? 'Aucune tâche terminée' : 'Rien à faire pour l\'instant',
                  message: _editor && !_onlyMine && !_showDone
                      ? 'Touche « Nouvelle tâche » pour confier quelque chose à une ou plusieurs personnes.'
                      : 'Les tâches qu\'on te confie apparaissent ici.',
                )
              else
                for (final t in shown)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: TaskCard(task: t, me: me, names: _names, showPeople: _editor, onTap: () => _open(t)),
                  ),
            ]),
          ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_editor ? 'Tâches' : 'Mes tâches')),
      floatingActionButton: _editor && _tasks != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Nouvelle tâche'),
              onPressed: _create,
            )
          : null,
      body: body,
    );
  }
}

/// Carte d'une tâche dans une liste.
class TaskCard extends StatelessWidget {
  final ChoirTask task;
  final String me;
  final Map<String, String> names;
  final bool showPeople;
  final VoidCallback onTap;

  const TaskCard({
    super.key,
    required this.task,
    required this.me,
    required this.names,
    required this.showPeople,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = task.assignee(me);
    final late = task.isLate();
    final doneCount = task.assignees.where((a) => a.status == TaskStatus.fait).length;
    final cant = task.assignees.where((a) => a.status == TaskStatus.impossible).length;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final status = mine?.status;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(children: [
            Icon(
              status != null ? statusIcon(status) : (task.isDone ? Icons.task_alt_rounded : Icons.assignment_rounded),
              color: status != null ? statusColor(status) : (task.isDone ? _doneColor : AppColors.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(task.title, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (task.dueDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      late ? 'En retard · ${dueLabel(task.dueDate!)}' : dueLabel(task.dueDate!),
                      style: muted?.copyWith(color: late ? _lateColor : null, fontWeight: late ? FontWeight.w600 : null),
                    ),
                  ),
                if (showPeople)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        task.assignees.map((a) => (names[a.profileId] ?? '?').split(' ').first).join(', '),
                        '$doneCount/${task.assignees.length} fait',
                        if (cant > 0) '$cant ne peut pas',
                      ].join(' · '),
                      style: muted?.copyWith(color: cant > 0 ? _cantColor : null),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

/// Détail d'une tâche : consigne, qui en est où, réponse de la personne et fil de messages.
class TaskScreen extends StatefulWidget {
  final Profile profile;
  final TasksBackend backend;
  final AgendaBackend agenda;
  final ChoirTask task;
  final List<Profile> members;

  const TaskScreen({
    super.key,
    required this.profile,
    required this.backend,
    required this.agenda,
    required this.task,
    required this.members,
  });

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  late ChoirTask _task = widget.task;
  List<TaskMessage>? _messages;
  ChoirEvent? _event;
  final _input = TextEditingController();
  bool _sending = false;

  Map<String, String> get _names => {for (final p in widget.members) p.id: p.fullName};
  String get _me => widget.profile.id;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadEvent();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final m = await widget.backend.messages(_task.id);
      if (mounted) setState(() => _messages = m);
    } catch (_) {
      if (mounted) setState(() => _messages = const []);
    }
  }

  Future<void> _loadEvent() async {
    if (_task.eventId == null) return;
    try {
      final events = await widget.agenda.events();
      if (mounted) setState(() => _event = events.where((e) => e.id == _task.eventId).firstOrNull);
    } catch (_) {}
  }

  Future<void> _reloadTask() async {
    final all = await widget.backend.tasks();
    final t = all.where((x) => x.id == _task.id).firstOrNull;
    if (t != null && mounted) setState(() => _task = t);
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _setStatus(TaskStatus s) async {
    try {
      await widget.backend.setMyStatus(_task.id, s);
      await _reloadTask();
      _snack(switch (s) {
        TaskStatus.fait => 'Bravo, c\'est noté !',
        TaskStatus.impossible => 'C\'est noté. Dis pourquoi dans les messages si tu veux.',
        TaskStatus.aFaire => 'La tâche est de nouveau à faire.',
      });
    } catch (e) {
      _snack('Réponse non enregistrée : ${explain(e)}');
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.backend.postMessage(_task.id, text);
      _input.clear();
      await _loadMessages();
    } catch (e) {
      _snack('Message non envoyé : ${explain(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteMessage(TaskMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Retirer ce message ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.backend.deleteMessage(m.id);
      await _loadMessages();
    } catch (e) {
      _snack('Impossible de retirer le message : ${explain(e)}');
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TaskFormScreen(backend: widget.backend, agenda: widget.agenda, members: widget.members, task: _task),
    ));
    if (saved == true) {
      await _reloadTask();
      _loadEvent();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette tâche ?'),
        content: const Text('Ses messages seront supprimés aussi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.backend.deleteTask(_task.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Impossible de supprimer : ${explain(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editor = widget.profile.isManager;
    final mine = _task.assignee(_me);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final late = _task.isLate();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tâche'),
        actions: [
          if (editor) IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_rounded), onPressed: _edit),
          if (editor) IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
            ContentWidth(
              maxWidth: 760,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(_task.title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                    [
                      'Confiée par ${(_names[_task.authorId] ?? 'un référent').split(' ').first}',
                      DateFormat('d MMM', 'fr_FR').format(_task.createdAt),
                    ].join(' · '),
                    style: muted,
                  ),
                  if (_task.dueDate != null) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(Icons.event_rounded, size: 18, color: late ? _lateColor : AppColors.gold),
                      const SizedBox(width: 8),
                      Text(late ? 'En retard · ${dueLabel(_task.dueDate!)}' : dueLabel(_task.dueDate!),
                          style: theme.textTheme.bodyMedium?.copyWith(color: late ? _lateColor : null)),
                    ]),
                  ],
                  if (_event != null) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(kindIcon(_event!.kind), size: 18, color: kindColor(_event!.kind)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${_event!.displayTitle} · ${formatDay(_event!.startsAt)}',
                            style: theme.textTheme.bodyMedium),
                      ),
                    ]),
                  ],
                  if (_task.details != null) ...[
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: SelectableText(_task.details!, style: theme.textTheme.bodyLarge),
                      ),
                    ),
                  ],
                  if (mine != null) ...[
                    const SizedBox(height: 18),
                    Text('Ta réponse', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    if (mine.status == TaskStatus.aFaire)
                      Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: _doneColor, minimumSize: const Size(0, 48)),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('C\'est fait'),
                            onPressed: () => _setStatus(TaskStatus.fait),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: _cantColor, minimumSize: const Size(0, 48)),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Je ne peux pas'),
                            onPressed: () => _setStatus(TaskStatus.impossible),
                          ),
                        ),
                      ])
                    else
                      Card(
                        child: ListTile(
                          leading: Icon(statusIcon(mine.status), color: statusColor(mine.status)),
                          title: Text(mine.status == TaskStatus.fait ? 'Tu as indiqué que c\'est fait' : 'Tu as indiqué que tu ne peux pas'),
                          trailing: TextButton(
                            onPressed: () => _setStatus(TaskStatus.aFaire),
                            child: const Text('Annuler'),
                          ),
                        ),
                      ),
                  ],
                  if (editor || _task.assignees.length > 1) ...[
                    const SizedBox(height: 18),
                    Text('Personnes chargées', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    for (final a in _task.assignees)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Avatar(_names[a.profileId] ?? '?', radius: 16),
                        title: Text(_names[a.profileId] ?? 'Ancien membre'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(statusIcon(a.status), color: statusColor(a.status), size: 18),
                          const SizedBox(width: 6),
                          Text(statusLabel(a.status), style: TextStyle(color: statusColor(a.status))),
                        ]),
                      ),
                  ],
                  const SizedBox(height: 18),
                  Text('Messages', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (_messages == null)
                    const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                  else if (_messages!.isEmpty)
                    Text('Pas encore de message. Pose une question ou donne des nouvelles ici.', style: muted)
                  else
                    for (final m in _messages!) _bubble(m, theme),
                ]),
              ),
            ),
          ]),
        ),
        SafeArea(
          top: false,
          child: ContentWidth(
            maxWidth: 760,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Écrire un message…'),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Envoyer',
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(TaskMessage m, ThemeData theme) {
    final mine = m.authorId == _me;
    final canDelete = mine || widget.profile.isManager;
    final bg = mine ? AppColors.aubergineLight : theme.colorScheme.surfaceContainerHighest;
    final fg = mine ? Colors.white : theme.colorScheme.onSurface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: canDelete ? () => _deleteMessage(m) : null,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine)
              Text((_names[m.authorId] ?? 'Ancien membre').split(' ').first,
                  style: theme.textTheme.labelMedium?.copyWith(color: AppColors.gold, fontWeight: FontWeight.w600)),
            Text(m.body, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
            const SizedBox(height: 2),
            Text(DateFormat('d MMM, HH:mm', 'fr_FR').format(m.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(color: fg.withValues(alpha: 0.7))),
          ]),
        ),
      ),
    );
  }
}
