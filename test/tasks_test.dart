import 'package:appli_gdc/models.dart';
import 'package:appli_gdc/screens/tasks_screen.dart';
import 'package:appli_gdc/services/agenda.dart';
import 'package:appli_gdc/services/tasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _chef = Profile(id: 'chef', fullName: 'Rayan Chef', role: MemberRole.responsable);
const _karim = Profile(id: 'karim', fullName: 'Karim Sono', role: MemberRole.membre);

class _FakeAgenda implements AgendaBackend {
  @override
  Future<List<Profile>> members() async => [_chef, _karim];
  @override
  Future<List<ChoirEvent>> events() async => [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTasks implements TasksBackend {
  final statuses = <TaskStatus>[];
  final saved = <List<String>>[];
  final posted = <String>[];
  TaskStatus status = TaskStatus.aFaire;

  ChoirTask get task => ChoirTask(
        id: 't1',
        title: 'Apporter la sono',
        details: 'Les 2 enceintes du local',
        authorId: 'chef',
        createdAt: DateTime(2026, 10, 14),
        assignees: [TaskAssignee(profileId: 'karim', status: status, updatedAt: DateTime(2026, 10, 14))],
      );

  @override
  Future<List<ChoirTask>> tasks() async => [task];
  @override
  Future<void> setMyStatus(String taskId, TaskStatus s) async {
    statuses.add(s);
    status = s;
  }

  @override
  Future<List<TaskMessage>> messages(String taskId) async => [];
  @override
  Future<void> postMessage(String taskId, String body) async => posted.add(body);
  @override
  Future<void> saveTask({
    String? id,
    required String title,
    String? details,
    DateTime? dueDate,
    String? eventId,
    required List<String> assigneeIds,
  }) async =>
      saved.add(assigneeIds);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('la personne chargée répond « C\'est fait » et écrit un message', (tester) async {
    final backend = _FakeTasks();
    await tester.pumpWidget(MaterialApp(
      home: TaskScreen(
          profile: _karim, backend: backend, agenda: _FakeAgenda(), task: backend.task, members: const [_chef, _karim]),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Apporter la sono'), findsOneWidget);
    expect(find.text('Les 2 enceintes du local'), findsOneWidget);

    await tester.tap(find.text('C\'est fait'));
    await tester.pumpAndSettle();
    expect(backend.statuses, [TaskStatus.fait]);
    expect(find.text('Tu as indiqué que c\'est fait'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6)); // la petite bannière disparaît
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Posées dans la salle');
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();
    expect(backend.posted, ['Posées dans la salle']);
  });

  testWidgets('une tâche ne part pas sans personne choisie', (tester) async {
    final backend = _FakeTasks();
    await tester.pumpWidget(MaterialApp(
      home: TaskFormScreen(backend: backend, agenda: _FakeAgenda(), members: const [_chef, _karim]),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Apporter la sono');
    await tester.ensureVisible(find.text('Envoyer la tâche'));
    await tester.tap(find.text('Envoyer la tâche'));
    await tester.pump();
    expect(find.text('Choisis au moins une personne'), findsOneWidget);
    expect(backend.saved, isEmpty);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Karim Sono'));
    await tester.tap(find.text('Karim Sono'));
    await tester.pump();
    await tester.ensureVisible(find.text('Envoyer la tâche'));
    await tester.tap(find.text('Envoyer la tâche'));
    await tester.pumpAndSettle();
    expect(backend.saved, [
      ['karim']
    ]);
  });

  test('tâche en retard seulement si quelqu\'un ne l\'a pas faite', () {
    ChoirTask t(TaskStatus s) => ChoirTask(
          id: 'x',
          title: 'x',
          dueDate: DateTime(2026, 10, 10),
          createdAt: DateTime(2026, 10, 1),
          assignees: [TaskAssignee(profileId: 'a', status: s, updatedAt: DateTime(2026, 10, 1))],
        );
    expect(t(TaskStatus.aFaire).isLate(DateTime(2026, 10, 14)), isTrue);
    expect(t(TaskStatus.fait).isLate(DateTime(2026, 10, 14)), isFalse);
    expect(t(TaskStatus.aFaire).isLate(DateTime(2026, 10, 10)), isFalse);
  });
}
