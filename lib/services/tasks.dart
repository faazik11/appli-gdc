import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'offline.dart';

/// Tâches confiées à certaines personnes, et le fil de messages de chaque tâche.
abstract class TasksBackend {
  /// Tâches visibles : toutes pour les éditeurs, les siennes pour un membre.
  Future<List<ChoirTask>> tasks();
  Future<void> saveTask({
    String? id,
    required String title,
    String? details,
    DateTime? dueDate,
    String? eventId,
    required List<String> assigneeIds,
  });
  Future<void> deleteTask(String id);
  Future<void> setMyStatus(String taskId, TaskStatus status);
  Future<List<TaskMessage>> messages(String taskId);
  Future<void> postMessage(String taskId, String body);
  Future<void> deleteMessage(String id);
}

class SupabaseTasks implements TasksBackend {
  SupabaseClient get _db => Supabase.instance.client;

  String? _clean(String? s) => (s?.trim().isEmpty ?? true) ? null : s!.trim();
  String? _day(DateTime? d) =>
      d == null ? null : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<List<ChoirTask>> tasks() async {
    final rows = await Offline.rows(
        'taches', () => _db.from('tasks').select('*, task_assignees(*)').order('created_at', ascending: false));
    return rows.map(ChoirTask.fromMap).toList();
  }

  @override
  Future<void> saveTask({
    String? id,
    required String title,
    String? details,
    DateTime? dueDate,
    String? eventId,
    required List<String> assigneeIds,
  }) async {
    final data = {
      'title': title.trim(),
      'details': _clean(details),
      'due_date': _day(dueDate),
      'event_id': eventId,
    };
    final String taskId;
    if (id == null) {
      final row = await _db.from('tasks').insert(data).select('id').single();
      taskId = row['id'] as String;
    } else {
      taskId = id;
      await _db.from('tasks').update(data).eq('id', id);
      // Retire les personnes qui ne sont plus chargées ; celles qui restent gardent leur réponse.
      final keep = assigneeIds.toSet();
      final current = (await _db.from('task_assignees').select('profile_id').eq('task_id', id) as List)
          .map((r) => r['profile_id'] as String)
          .toSet();
      final gone = current.difference(keep).toList();
      if (gone.isNotEmpty) {
        await _db.from('task_assignees').delete().eq('task_id', id).inFilter('profile_id', gone);
      }
      assigneeIds = keep.difference(current).toList();
    }
    if (assigneeIds.isNotEmpty) {
      await _db.from('task_assignees').insert([
        for (final p in assigneeIds) {'task_id': taskId, 'profile_id': p},
      ]);
    }
  }

  @override
  Future<void> deleteTask(String id) => _db.from('tasks').delete().eq('id', id);

  @override
  Future<void> setMyStatus(String taskId, TaskStatus status) =>
      _db.rpc('set_task_status', params: {'p_task': taskId, 'p_status': taskStatusToDb(status)});

  @override
  Future<List<TaskMessage>> messages(String taskId) async {
    final rows = await Offline.rows('tache-$taskId',
        () => _db.from('task_messages').select().eq('task_id', taskId).order('created_at'));
    return rows.map(TaskMessage.fromMap).toList();
  }

  @override
  Future<void> postMessage(String taskId, String body) =>
      _db.from('task_messages').insert({'task_id': taskId, 'body': body.trim()});

  @override
  Future<void> deleteMessage(String id) => _db.from('task_messages').delete().eq('id', id);
}
