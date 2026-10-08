import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

/// Données de l'agenda (répétitions, prestations, réponses et présences).
abstract class AgendaBackend {
  Future<List<ChoirEvent>> events();
  Future<List<Profile>> members();
  Future<void> saveEvent({
    String? id,
    required EventKind kind,
    String? title,
    required DateTime startsAt,
    DateTime? endsAt,
    String? location,
    String? notes,
  });
  Future<void> deleteEvent(String id);
  Future<void> setResponse(String eventId, String profileId, EventResponse response);
  Future<void> setAttended(String eventId, String profileId, bool? attended);
}

class SupabaseAgenda implements AgendaBackend {
  SupabaseClient get _db => Supabase.instance.client;

  String? _clean(String? s) => (s?.trim().isEmpty ?? true) ? null : s!.trim();

  @override
  Future<List<ChoirEvent>> events() async {
    final r = await Future.wait<dynamic>([
      _db.from('events').select('*, event_participants(*)').order('starts_at').then((v) => v),
      _db.rpc('event_counts').then((v) => v),
    ]);
    final summaries = {
      for (final c in (r[1] as List).cast<Map<String, dynamic>>()) c['event_id'] as String: EventSummary.fromMap(c),
    };
    return (r[0] as List)
        .cast<Map<String, dynamic>>()
        .map((m) => ChoirEvent.fromMap(m).withSummary(summaries[m['id']] ?? const EventSummary()))
        .toList();
  }

  @override
  Future<List<Profile>> members() async {
    final rows = await _db.from('profiles').select().neq('role', 'en_attente').order('full_name');
    return rows.map(Profile.fromMap).toList();
  }

  @override
  Future<void> saveEvent({
    String? id,
    required EventKind kind,
    String? title,
    required DateTime startsAt,
    DateTime? endsAt,
    String? location,
    String? notes,
  }) async {
    final data = {
      'kind': kind.name,
      'title': _clean(title),
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
      'location': _clean(location),
      'notes': _clean(notes),
    };
    if (id == null) {
      await _db.from('events').insert(data);
    } else {
      await _db.from('events').update(data).eq('id', id);
    }
  }

  @override
  Future<void> deleteEvent(String id) => _db.from('events').delete().eq('id', id);

  @override
  Future<void> setResponse(String eventId, String profileId, EventResponse response) => _db
      .from('event_participants')
      .upsert({'event_id': eventId, 'profile_id': profileId, 'response': responseToDb(response)});

  @override
  Future<void> setAttended(String eventId, String profileId, bool? attended) => _db
      .from('event_participants')
      .upsert({'event_id': eventId, 'profile_id': profileId, 'attended': attended});
}
