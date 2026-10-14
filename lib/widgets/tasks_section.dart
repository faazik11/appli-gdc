import 'package:flutter/material.dart';

import '../models.dart';
import '../screens/tasks_screen.dart';
import '../services/agenda.dart';
import '../services/tasks.dart';
import '../theme.dart';
import 'ui.dart';

/// Accueil : les tâches à faire de la personne, et pour l'admin et le responsable le suivi de celles confiées.
class TasksSection extends StatefulWidget {
  final Profile profile;
  final TasksBackend backend;
  final AgendaBackend agenda;

  const TasksSection({super.key, required this.profile, required this.backend, required this.agenda});

  @override
  State<TasksSection> createState() => _TasksSectionState();
}

class _TasksSectionState extends State<TasksSection> {
  List<ChoirTask>? _tasks;
  List<Profile> _members = const [];

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
      });
    } catch (_) {
      // L'accueil reste utilisable sans les tâches.
    }
  }

  Future<void> _openList() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TasksScreen(profile: widget.profile, backend: widget.backend, agenda: widget.agenda),
    ));
    _load();
  }

  Future<void> _openTask(ChoirTask t) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TaskScreen(
          profile: widget.profile, backend: widget.backend, agenda: widget.agenda, task: t, members: _members),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    if (tasks == null) return const SizedBox.shrink();
    final me = widget.profile.id;
    final editor = widget.profile.isManager;
    final todo = tasks.where((t) => t.assignee(me)?.status == TaskStatus.aFaire).toList()
      ..sort((a, b) => (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999)));
    // Sans tâche en cours on ne voit rien ; l'admin et le responsable gardent l'accès au suivi.
    if (!editor && todo.isEmpty) return const SizedBox.shrink();
    final names = {for (final p in _members) p.id: p.fullName};
    final open = tasks.where((t) => !t.isDone).toList();
    final late = open.where((t) => t.isLate()).length;
    final cant = open.where((t) => t.assignees.any((a) => a.status == TaskStatus.impossible)).length;
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(todo.isEmpty ? 'Tâches' : 'Mes tâches', actionLabel: 'Tout voir', onAction: _openList),
      for (final t in todo.take(3))
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: TaskCard(task: t, me: me, names: names, showPeople: false, onTap: () => _openTask(t)),
        ),
      if (todo.length > 3)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _openList, child: Text('Voir mes ${todo.length} tâches')),
          ),
        ),
      if (editor)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              leading: const Icon(Icons.assignment_turned_in_rounded, color: AppColors.gold),
              title: Text(open.isEmpty ? 'Aucune tâche en cours' : '${open.length} tâche${open.length > 1 ? 's' : ''} en cours'),
              subtitle: Text(
                [
                  if (late > 0) '$late en retard',
                  if (cant > 0) '$cant avec un « je ne peux pas »',
                  if (late == 0 && cant == 0) 'Confie une tâche précise à une ou plusieurs personnes',
                ].join(' · '),
                style: (late > 0 || cant > 0) ? TextStyle(color: theme.colorScheme.error) : null,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _openList,
            ),
          ),
        ),
    ]);
  }
}
