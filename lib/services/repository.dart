import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Accès aux données de la chorale (tables + fichiers Supabase).
class Repository {
  Repository._();
  static final instance = Repository._();

  static const lyricsBucket = 'lyrics';
  static const audioBucket = 'audio';
  static const bookletsBucket = 'booklets';

  Future<Profile?> currentProfile() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final row = await _db.from('profiles').select().eq('id', user.id).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<List<Profile>> profiles() async {
    final rows = await _db.from('profiles').select().order('full_name');
    return rows.map(Profile.fromMap).toList();
  }

  Future<void> setRole(String profileId, MemberRole role) =>
      _db.from('profiles').update({'role': roleToDb(role)}).eq('id', profileId);

  Future<List<Category>> categories() async {
    final rows = await _db.from('categories').select().order('position');
    return rows.map(Category.fromMap).toList();
  }

  Future<List<Song>> songs() async {
    final rows = await _db.from('songs').select().order('title');
    return rows.map(Song.fromMap).toList();
  }

  Future<void> saveSong({
    String? id,
    required String title,
    required int categoryId,
    String? youtubeUrl,
    String? notes,
    List<String> tags = const [],
    String? lyricsPdfPath,
    String? audioPath,
  }) async {
    final data = {
      'title': title,
      'category_id': categoryId,
      'youtube_url': (youtubeUrl?.trim().isEmpty ?? true) ? null : youtubeUrl!.trim(),
      'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
      'tags': tags,
      'lyrics_pdf_path': lyricsPdfPath,
      'audio_path': audioPath,
    };
    if (id == null) {
      await _db.from('songs').insert(data);
    } else {
      await _db.from('songs').update(data).eq('id', id);
    }
  }

  Future<void> deleteSong(Song song) async {
    await _db.from('songs').delete().eq('id', song.id);
    if (song.lyricsPdfPath != null) {
      await _db.storage.from(lyricsBucket).remove([song.lyricsPdfPath!]);
    }
    if (song.audioPath != null) {
      await _db.storage.from(audioBucket).remove([song.audioPath!]);
    }
  }

  Future<List<Booklet>> booklets() async {
    final rows = await _db
        .from('booklets')
        .select()
        .order('event_date', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false);
    return rows.map(Booklet.fromMap).toList();
  }

  Future<String> saveBooklet({
    String? id,
    required String title,
    DateTime? eventDate,
    required List<BookletPart> parts,
    String? pdfPath,
  }) async {
    final data = {
      'title': title,
      'event_date': eventDate?.toIso8601String().substring(0, 10),
      'structure': parts.map((p) => p.toJson()).toList(),
      'pdf_path': pdfPath,
    };
    if (id == null) {
      final row = await _db.from('booklets').insert(data).select('id').single();
      return row['id'] as String;
    }
    await _db.from('booklets').update(data).eq('id', id);
    return id;
  }

  Future<void> deleteBooklet(Booklet booklet) async {
    await _db.from('booklets').delete().eq('id', booklet.id);
    if (booklet.pdfPath != null) {
      await _db.storage.from(bookletsBucket).remove([booklet.pdfPath!]);
    }
  }

  /// Dépose un fichier et renvoie son chemin dans le bucket.
  Future<String> upload(String bucket, String fileName, Uint8List bytes, String contentType) async {
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }

  Future<void> deleteFiles(String bucket, List<String> paths) =>
      _db.storage.from(bucket).remove(paths);

  Future<Uint8List> download(String bucket, String path) =>
      _db.storage.from(bucket).download(path);

  /// Lien temporaire (1 h) pour lire ou télécharger un fichier privé.
  Future<String> signedUrl(String bucket, String path) =>
      _db.storage.from(bucket).createSignedUrl(path, 3600);
}

String audioContentType(String? extension) => switch (extension?.toLowerCase()) {
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/x-m4a',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'flac' => 'audio/flac',
      _ => 'audio/mpeg',
    };
