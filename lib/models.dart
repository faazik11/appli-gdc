/// `chef` est la valeur historique en base du Référent Chant Français.
enum MemberRole { admin, responsable, chef, referentArabe, referentSono, referentArtistique, referentDouf, membre, enAttente }

MemberRole roleFromDb(String value) => switch (value) {
      'admin' => MemberRole.admin,
      'responsable' => MemberRole.responsable,
      'chef' => MemberRole.chef,
      'referent_arabe' => MemberRole.referentArabe,
      'referent_sono' => MemberRole.referentSono,
      'referent_artistique' => MemberRole.referentArtistique,
      'referent_douf' => MemberRole.referentDouf,
      'membre' => MemberRole.membre,
      _ => MemberRole.enAttente,
    };

String roleToDb(MemberRole role) => switch (role) {
      MemberRole.admin => 'admin',
      MemberRole.responsable => 'responsable',
      MemberRole.chef => 'chef',
      MemberRole.referentArabe => 'referent_arabe',
      MemberRole.referentSono => 'referent_sono',
      MemberRole.referentArtistique => 'referent_artistique',
      MemberRole.referentDouf => 'referent_douf',
      MemberRole.membre => 'membre',
      MemberRole.enAttente => 'en_attente',
    };

String roleLabel(MemberRole role) => switch (role) {
      MemberRole.admin => 'Admin',
      MemberRole.responsable => 'Responsable',
      MemberRole.chef => 'Référent Chant Français',
      MemberRole.referentArabe => 'Référent Chant Arabe',
      MemberRole.referentSono => 'Référent Sono',
      MemberRole.referentArtistique => 'Référent Artistique',
      MemberRole.referentDouf => 'Référent Douf',
      MemberRole.membre => 'Membre',
      MemberRole.enAttente => 'En attente',
    };

class Profile {
  final String id;
  final String fullName;
  final MemberRole role;

  const Profile({required this.id, required this.fullName, required this.role});

  bool get isEditor => isApproved && role != MemberRole.membre;
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

  /// Note de départ enregistrée au micro (bucket « enregistrements »).
  final String? noteAudioPath;

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
    this.noteAudioPath,
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
        noteAudioPath: m['note_audio_path'] as String?,
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

  /// Tenue du jour.
  final String? outfitId;

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
    this.outfitId,
    this.summary,
  });

  ChoirEvent withSummary(EventSummary? s, {List<Participant>? participants}) =>
      copyWith(participants: participants, summary: s);

  ChoirEvent copyWith({List<Participant>? participants, EventSummary? summary, String? outfitId}) => ChoirEvent(
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
        outfitId: outfitId ?? this.outfitId,
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
        outfitId: m['outfit_id'] as String?,
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

  /// Fin d'affichage sur l'accueil (null : jusqu'à ce qu'on la retire).
  final DateTime? expiresAt;

  const Announcement({required this.id, required this.body, this.authorId, required this.createdAt, this.expiresAt});

  bool isActive([DateTime? now]) => expiresAt == null || expiresAt!.isAfter(now ?? DateTime.now());

  factory Announcement.fromMap(Map<String, dynamic> m) => Announcement(
        id: m['id'] as String,
        body: m['body'] as String,
        authorId: m['created_by'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        expiresAt: m['expires_at'] == null ? null : DateTime.parse(m['expires_at'] as String).toLocal(),
      );
}

/// Catégorie de matériel créée par le chef de chœur (Enceintes, Micros…).
class EquipmentCategory {
  final String id;
  final String name;

  const EquipmentCategory({required this.id, required this.name});

  factory EquipmentCategory.fromMap(Map<String, dynamic> m) =>
      EquipmentCategory(id: m['id'] as String, name: m['name'] as String);
}

/// Fiche produit de l'inventaire du local.
class EquipmentItem {
  final String id;
  final String name;
  final String? categoryId;
  final int quantity;
  final String? notes;
  final String? photoPath;

  const EquipmentItem({
    required this.id,
    required this.name,
    this.categoryId,
    this.quantity = 1,
    this.notes,
    this.photoPath,
  });

  factory EquipmentItem.fromMap(Map<String, dynamic> m) => EquipmentItem(
        id: m['id'] as String,
        name: m['name'] as String,
        categoryId: m['category_id'] as String?,
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        notes: m['notes'] as String?,
        photoPath: m['photo_path'] as String?,
      );
}

/// Tenue réutilisable (ex. « Tenue noire ») : photo d'ensemble et éléments, chacun avec sa petite photo.
class Outfit {
  final String id;
  final String name;
  final String? notes;
  final String? photoPath;
  final List<OutfitItem> items;

  const Outfit({required this.id, required this.name, this.notes, this.photoPath, this.items = const []});

  factory Outfit.fromMap(Map<String, dynamic> m) => Outfit(
        id: m['id'] as String,
        name: m['name'] as String,
        notes: m['notes'] as String?,
        photoPath: m['photo_path'] as String?,
        items: (((m['outfit_items'] as List?) ?? const [])
                .map((e) => OutfitItem.fromMap(Map<String, dynamic>.from(e as Map)))
                .toList())
          ..sort((a, b) => a.position.compareTo(b.position)),
      );
}

/// Vêtement de la liste (chemise blanche, chaussettes noires…), avec sa photo.
class Garment {
  final String id;
  final String name;
  final String? photoPath;

  const Garment({required this.id, required this.name, this.photoPath});

  factory Garment.fromMap(Map<String, dynamic> m) => Garment(
        id: m['id'] as String,
        name: m['name'] as String,
        photoPath: m['photo_path'] as String?,
      );
}

/// Élément d'une tenue : un vêtement de la liste (son nom et sa photo viennent du vêtement).
class OutfitItem {
  final String? id;
  final String? garmentId;
  final String label;
  final String? photoPath;
  final int position;

  const OutfitItem({this.id, this.garmentId, required this.label, this.photoPath, this.position = 0});

  factory OutfitItem.fromGarment(Garment g) => OutfitItem(garmentId: g.id, label: g.name, photoPath: g.photoPath);

  factory OutfitItem.fromMap(Map<String, dynamic> m) {
    final g = m['garments'] is Map ? Map<String, dynamic>.from(m['garments'] as Map) : null;
    return OutfitItem(
      id: m['id'] as String?,
      garmentId: m['garment_id'] as String?,
      label: (g?['name'] ?? m['label']) as String,
      photoPath: (g == null ? m['photo_path'] : g['photo_path']) as String?,
      position: (m['position'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Matériel à emporter pour un événement, coché une fois chargé.
class EventGear {
  final String equipmentId;
  final int quantity;
  final bool packed;

  const EventGear({required this.equipmentId, this.quantity = 1, this.packed = false});

  factory EventGear.fromMap(Map<String, dynamic> m) => EventGear(
        equipmentId: m['equipment_id'] as String,
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        packed: m['packed'] as bool? ?? false,
      );
}

/// Enregistrement d'une répétition, daté automatiquement, avec les points abordés.
class Recording {
  final String id;
  final DateTime recordedAt;
  final String? eventId;
  final String? title;
  final String? notes;
  final String audioPath;
  final int? durationSeconds;

  const Recording({
    required this.id,
    required this.recordedAt,
    this.eventId,
    this.title,
    this.notes,
    required this.audioPath,
    this.durationSeconds,
  });

  factory Recording.fromMap(Map<String, dynamic> m) => Recording(
        id: m['id'] as String,
        recordedAt: DateTime.parse(m['recorded_at'] as String).toLocal(),
        eventId: m['event_id'] as String?,
        title: m['title'] as String?,
        notes: m['notes'] as String?,
        audioPath: m['audio_path'] as String,
        durationSeconds: (m['duration_seconds'] as num?)?.toInt(),
      );
}

/// Où en est une personne chargée d'une tâche.
enum TaskStatus { aFaire, fait, impossible }

TaskStatus taskStatusFromDb(String? v) => switch (v) {
      'fait' => TaskStatus.fait,
      'impossible' => TaskStatus.impossible,
      _ => TaskStatus.aFaire,
    };

String taskStatusToDb(TaskStatus s) => switch (s) {
      TaskStatus.aFaire => 'a_faire',
      TaskStatus.fait => 'fait',
      TaskStatus.impossible => 'impossible',
    };

class TaskAssignee {
  final String profileId;
  final TaskStatus status;
  final DateTime updatedAt;

  const TaskAssignee({required this.profileId, required this.status, required this.updatedAt});

  factory TaskAssignee.fromMap(Map<String, dynamic> m) => TaskAssignee(
        profileId: m['profile_id'] as String,
        status: taskStatusFromDb(m['status'] as String?),
        updatedAt: DateTime.parse(m['updated_at'] as String).toLocal(),
      );
}

/// Tâche précise confiée par le Responsable ou un Référent à certaines personnes.
class ChoirTask {
  final String id;
  final String title;
  final String? details;
  final DateTime? dueDate;
  final String? eventId;
  final String? authorId;
  final DateTime createdAt;
  final List<TaskAssignee> assignees;

  const ChoirTask({
    required this.id,
    required this.title,
    this.details,
    this.dueDate,
    this.eventId,
    this.authorId,
    required this.createdAt,
    this.assignees = const [],
  });

  TaskAssignee? assignee(String profileId) => assignees.where((a) => a.profileId == profileId).firstOrNull;

  /// Terminée quand plus personne n'a la tâche « à faire ».
  bool get isDone => assignees.isNotEmpty && assignees.every((a) => a.status != TaskStatus.aFaire);

  /// Date limite passée alors que quelqu'un ne l'a pas encore faite.
  bool isLate([DateTime? now]) {
    if (dueDate == null || isDone) return false;
    final n = now ?? DateTime.now();
    return dueDate!.isBefore(DateTime(n.year, n.month, n.day));
  }

  factory ChoirTask.fromMap(Map<String, dynamic> m) => ChoirTask(
        id: m['id'] as String,
        title: m['title'] as String,
        details: m['details'] as String?,
        dueDate: m['due_date'] == null ? null : DateTime.parse(m['due_date'] as String),
        eventId: m['event_id'] as String?,
        authorId: m['created_by'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        assignees: ((m['task_assignees'] as List?) ?? const [])
            .map((e) => TaskAssignee.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class TaskMessage {
  final String id;
  final String? authorId;
  final String body;
  final DateTime createdAt;

  const TaskMessage({required this.id, this.authorId, required this.body, required this.createdAt});

  factory TaskMessage.fromMap(Map<String, dynamic> m) => TaskMessage(
        id: m['id'] as String,
        authorId: m['author_id'] as String?,
        body: m['body'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}
