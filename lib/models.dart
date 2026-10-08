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
