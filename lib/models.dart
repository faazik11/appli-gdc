enum MemberRole { admin, chef, membre, enAttente }

MemberRole roleFromDb(String value) => switch (value) {
      'admin' => MemberRole.admin,
      'chef' => MemberRole.chef,
      'membre' => MemberRole.membre,
      _ => MemberRole.enAttente,
    };

String roleToDb(MemberRole role) => switch (role) {
      MemberRole.admin => 'admin',
      MemberRole.chef => 'chef',
      MemberRole.membre => 'membre',
      MemberRole.enAttente => 'en_attente',
    };

String roleLabel(MemberRole role) => switch (role) {
      MemberRole.admin => 'Admin',
      MemberRole.chef => 'Chef de chœur',
      MemberRole.membre => 'Membre',
      MemberRole.enAttente => 'En attente',
    };

class Profile {
  final String id;
  final String fullName;
  final MemberRole role;

  const Profile({required this.id, required this.fullName, required this.role});

  bool get isEditor => role == MemberRole.admin || role == MemberRole.chef;
  bool get isAdmin => role == MemberRole.admin;
  bool get isApproved => role != MemberRole.enAttente;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        fullName: m['full_name'] as String? ?? '',
        role: roleFromDb(m['role'] as String),
      );
}

class Category {
  final int id;
  final String name;

  const Category({required this.id, required this.name});

  bool get isBooklets => name == 'Livrets';

  factory Category.fromMap(Map<String, dynamic> m) =>
      Category(id: m['id'] as int, name: m['name'] as String);
}

class Song {
  final String id;
  final String title;
  final int categoryId;
  final String? lyricsPdfPath;
  final String? youtubeUrl;
  final String? audioPath;
  final List<String> tags;
  final String? notes;
  final DateTime? createdAt;

  const Song({
    required this.id,
    required this.title,
    required this.categoryId,
    this.lyricsPdfPath,
    this.youtubeUrl,
    this.audioPath,
    this.tags = const [],
    this.notes,
    this.createdAt,
  });

  bool get hasPdf => lyricsPdfPath != null;
  bool get hasYoutube => youtubeUrl != null;
  bool get hasAudio => audioPath != null;

  factory Song.fromMap(Map<String, dynamic> m) => Song(
        id: m['id'] as String,
        title: m['title'] as String,
        categoryId: m['category_id'] as int,
        lyricsPdfPath: m['lyrics_pdf_path'] as String?,
        youtubeUrl: m['youtube_url'] as String?,
        audioPath: m['audio_path'] as String?,
        tags: (m['tags'] as List?)?.cast<String>() ?? const [],
        notes: m['notes'] as String?,
        createdAt: m['created_at'] == null ? null : DateTime.parse(m['created_at'] as String),
      );
}

/// Une partie d'un livret (ex. « Entrée ») et ses chants, dans l'ordre.
class BookletPart {
  String name;
  final List<String> songIds;

  BookletPart({required this.name, List<String>? songIds}) : songIds = songIds ?? [];

  Map<String, dynamic> toJson() => {'part': name, 'songs': songIds};

  factory BookletPart.fromJson(Map<String, dynamic> m) => BookletPart(
        name: m['part'] as String? ?? '',
        songIds: (m['songs'] as List?)?.cast<String>() ?? [],
      );
}

class Booklet {
  final String id;
  final String title;
  final DateTime? eventDate;
  final List<BookletPart> parts;
  final String? pdfPath;
  final DateTime? createdAt;

  const Booklet({
    required this.id,
    required this.title,
    this.eventDate,
    this.parts = const [],
    this.pdfPath,
    this.createdAt,
  });

  int get songCount => parts.fold(0, (n, p) => n + p.songIds.length);

  factory Booklet.fromMap(Map<String, dynamic> m) => Booklet(
        id: m['id'] as String,
        title: m['title'] as String,
        eventDate: m['event_date'] == null ? null : DateTime.parse(m['event_date'] as String),
        parts: ((m['structure'] as List?) ?? const [])
            .map((e) => BookletPart.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        pdfPath: m['pdf_path'] as String?,
        createdAt: m['created_at'] == null ? null : DateTime.parse(m['created_at'] as String),
      );
}

enum EventKind { repetition, prestation }

enum EventResponse { present, peutEtre, absent }

EventResponse? responseFromDb(String? value) => switch (value) {
      'present' => EventResponse.present,
      'peut_etre' => EventResponse.peutEtre,
      'absent' => EventResponse.absent,
      _ => null,
    };

String responseToDb(EventResponse r) => switch (r) {
      EventResponse.present => 'present',
      EventResponse.peutEtre => 'peut_etre',
      EventResponse.absent => 'absent',
    };

/// Réponse d'un membre à un événement, et sa présence réelle notée par le chef.
class Participant {
  final String profileId;
  final EventResponse? response;
  final bool? attended;

  const Participant({required this.profileId, this.response, this.attended});

  factory Participant.fromMap(Map<String, dynamic> m) => Participant(
        profileId: m['profile_id'] as String,
        response: responseFromDb(m['response'] as String?),
        attended: m['attended'] as bool?,
      );
}

/// Totaux d'un événement, visibles de tous (sans les noms).
class EventSummary {
  final int present;
  final int peutEtre;
  final int absent;
  final int attended;
  final bool rollCallDone;

  const EventSummary({this.present = 0, this.peutEtre = 0, this.absent = 0, this.attended = 0, this.rollCallDone = false});

  factory EventSummary.fromMap(Map<String, dynamic> m) => EventSummary(
        present: m['present'] as int? ?? 0,
        peutEtre: m['peut_etre'] as int? ?? 0,
        absent: m['absent'] as int? ?? 0,
        attended: m['attended'] as int? ?? 0,
        rollCallDone: m['roll_call_done'] as bool? ?? false,
      );
}

/// Répétition ou prestation de l'agenda.
class ChoirEvent {
  final String id;
  final EventKind kind;
  final String? title;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? location;
  final String? notes;
  final List<Participant> participants;

  /// Chants à travailler (répétition) ou programme (prestation).
  final List<String> songIds;
  final String? bookletId;

  /// Totaux calculés côté serveur ; un simple membre ne reçoit que sa propre ligne de participants.
  final EventSummary? summary;

  const ChoirEvent({
    required this.id,
    required this.kind,
    required this.startsAt,
    this.title,
    this.endsAt,
    this.location,
    this.notes,
    this.participants = const [],
    this.songIds = const [],
    this.bookletId,
    this.summary,
  });

  ChoirEvent withSummary(EventSummary? s, {List<Participant>? participants}) =>
      copyWith(participants: participants, summary: s);

  ChoirEvent copyWith({List<Participant>? participants, EventSummary? summary}) => ChoirEvent(
        id: id,
        kind: kind,
        title: title,
        startsAt: startsAt,
        endsAt: endsAt,
        location: location,
        notes: notes,
        participants: participants ?? this.participants,
        songIds: songIds,
        bookletId: bookletId,
        summary: summary ?? this.summary,
      );

  bool get isRehearsal => kind == EventKind.repetition;
  String get displayTitle =>
      (title?.trim().isNotEmpty ?? false) ? title!.trim() : (isRehearsal ? 'Répétition' : 'Prestation');

  /// Encore à venir tant qu'il n'est pas terminé (3 h par défaut sans heure de fin).
  bool get isUpcoming => (endsAt ?? startsAt.add(const Duration(hours: 3))).isAfter(DateTime.now());

  /// L'appel a été fait si au moins une présence est notée.
  bool get rollCallDone => summary?.rollCallDone ?? participants.any((p) => p.attended != null);

  Participant? participantOf(String profileId) => participants.where((p) => p.profileId == profileId).firstOrNull;
  int count(EventResponse r) =>
      summary == null
          ? participants.where((p) => p.response == r).length
          : switch (r) {
              EventResponse.present => summary!.present,
              EventResponse.peutEtre => summary!.peutEtre,
              EventResponse.absent => summary!.absent,
            };
  int get attendedCount => summary?.attended ?? participants.where((p) => p.attended == true).length;

  factory ChoirEvent.fromMap(Map<String, dynamic> m) => ChoirEvent(
        id: m['id'] as String,
        kind: m['kind'] == 'prestation' ? EventKind.prestation : EventKind.repetition,
        title: m['title'] as String?,
        startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
        endsAt: m['ends_at'] == null ? null : DateTime.parse(m['ends_at'] as String).toLocal(),
        location: m['location'] as String?,
        notes: m['notes'] as String?,
        songIds: (m['song_ids'] as List?)?.cast<String>() ?? const [],
        bookletId: m['booklet_id'] as String?,
        participants: ((m['event_participants'] as List?) ?? const [])
            .map((e) => Participant.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Message du chef de chœur affiché sur l'accueil.
class Announcement {
  final String id;
  final String body;
  final String? authorId;
  final DateTime createdAt;

  const Announcement({required this.id, required this.body, this.authorId, required this.createdAt});

  factory Announcement.fromMap(Map<String, dynamic> m) => Announcement(
        id: m['id'] as String,
        body: m['body'] as String,
        authorId: m['created_by'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}
