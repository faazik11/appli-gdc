import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/agenda.dart';
import '../services/errors.dart';
import '../services/tasks.dart';
import '../widgets/event_widgets.dart';
import '../widgets/ui.dart';

/// Création ou modification d'une tâche.
class TaskFormScreen extends StatefulWidget {
  final TasksBackend backend;
  final AgendaBackend agenda;
  final List<Profile> members;
  final ChoirTask? task;

  const TaskFormScreen({super.key, required this.backend, required this.agenda, required this.members, this.task});

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  late final _title = TextEditingController(text: widget.task?.title);
  late final _details = TextEditingController(text: widget.task?.details);
  late DateTime? _due = widget.task?.dueDate;
  late String? _eventId = widget.task?.eventId;
  late final Set<String> _people = {...?widget.task?.assignees.map((a) => a.profileId)};
  List<ChoirEvent> _events = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    try {
      final all = await widget.agenda.events();
      final now = DateTime.now().subtract(const Duration(days: 1));
      if (mounted) {
        setState(() => _events = all.where((e) => e.startsAt.isAfter(now) || e.id == _eventId).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt)));
      }
    } catch (_) {}
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('fr', 'FR'),
      initialDate: _due ?? now.add(const Duration(days: 3)),
      firstDate: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Écris ce qu\'il faut faire')));
      return;
    }
    if (_people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choisis au moins une personne')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.backend.saveTask(
        id: widget.task?.id,
        title: _title.text,
        details: _details.text,
        dueDate: _due,
        eventId: _eventId,
        assigneeIds: _people.toList(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tâche non enregistrée : ${explain(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.task != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Modifier la tâche' : 'Nouvelle tâche')),
      body: ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 100), children: [
        ContentWidth(
          maxWidth: 640,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Ce qu\'il faut faire',
                  hintText: 'Ex. Apporter la sono',
                  prefixIcon: Icon(Icons.assignment_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _details,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Consigne précise (facultatif)',
                  hintText: 'Ex. Récupérer les 2 enceintes au local samedi avant 14h et les installer dans la salle.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              Text('Pour qui ?', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in widget.members)
                  FilterChip(
                    avatar: _people.contains(p.id) ? null : Avatar(p.fullName, radius: 11),
                    label: Text(p.fullName.isEmpty ? 'Sans nom' : p.fullName),
                    selected: _people.contains(p.id),
                    onSelected: (v) => setState(() => v ? _people.add(p.id) : _people.remove(p.id)),
                  ),
              ]),
              const SizedBox(height: 20),
              Text('Pour quand ?', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_rounded),
                  title: Text(_due == null ? 'Pas de date limite' : 'Avant le ${formatDay(_due!)}'),
                  subtitle: _due == null ? null : const Text('Rappel automatique la veille à 18h'),
                  trailing: _due == null
                      ? const Icon(Icons.edit_calendar_rounded)
                      : IconButton(
                          tooltip: 'Retirer la date',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() => _due = null),
                        ),
                  onTap: _pickDue,
                ),
              ),
              if (_events.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Pour un événement ? (facultatif)', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _eventId,
                  isExpanded: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.star_outline_rounded)),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Aucun')),
                    for (final e in _events)
                      DropdownMenuItem(
                        value: e.id,
                        child: Text('${e.displayTitle} · ${DateFormat('d MMM', 'fr_FR').format(e.startsAt)}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _eventId = v),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.send_rounded),
                label: Text(editing ? 'Enregistrer' : 'Envoyer la tâche'),
              ),
              if (!editing) ...[
                const SizedBox(height: 8),
                Text('Les personnes choisies reçoivent une notification sur leur téléphone.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
