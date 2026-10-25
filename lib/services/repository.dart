import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'offline.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Accès aux données de la chorale (tables + fichiers Supabase).
class Repository {
  Repository._();
  static final instance = Repository._();

  static const lyricsBucket = 'lyrics';
  static const audioBucket = 'audio';
  static const bookletsBucket = 'booklets';
  static const notesBucket = 'enregistrements';

  /// Espaces rangés chez Cloudflare R2 (10 Go gratuits) au lieu de Supabase (1 Go) :
  /// les enregistrements de répète et les notes des chants. La fonction « fichiers » donne
  /// des liens signés ; l'appli ne connaît pas les clés R2.
  static const r2Buckets = {notesBucket};

  static Future<Map<String, dynamic>> r2(Map<String, dynamic> body) async {
    final r = await _db.functions.invoke('fichiers', body: body);
    return Map<String, dynamic>.from(r.data as Map);
  }

  static Future<String> _r2Url(String action, String path, [String? type]) async =>
      (await r2({'action': action, 'path': path, if (type != null) 'type': type}))['url'] as String;

  static void _check(http.BaseResponse r) {
    if (r.statusCode >= 300) throw StorageException('Cloudflare R2 a répondu ${r.statusCode}', statusCode: '${r.statusCode}');
  }

  Future<Profile?> currentProfile() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final rows = await Offline.rows('profil', () => _db.from('profiles').select().eq('id', user.id));
    if (rows.isEmpty) return null;
    await Offline.saveLastProfile(rows.first);
    return Profile.fromMap(rows.first);
  }

  Future<List<Profile>> profiles() async {
    final rows = await Offline.rows('profils', () => _db.from('profiles').select().order('full_name'));
    return rows.map(Profile.fromMap).toList();
  }

  Future<void> setRole(String profileId, MemberRole role) =>
      _db.from('profiles').update({'role': roleToDb(role)}).eq('id', profileId);

  Future<List<Category>> categories() async {
    final rows = await Offline.rows('categories', () => _db.from('categories').select().order('position'));
    return rows.map(Category.fromMap).toList();
  }

  Future<List<Song>> songs() async {
    final rows = await Offline.rows('chants', () => _db.from('songs').select().order('title'));
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
    bool notifyMembers = false,
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
      final row = await _db.from('songs').insert(data).select('id').single();
      // Seulement à l'ajout, et si on l'a choisi : jamais lors d'une modification.
      if (notifyMembers) {
        await _db.rpc('notify_new_song', params: {'p_song_id': row['id']});
      }
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
    if (song.noteAudioPath != null) {
      await deleteFiles(notesBucket, [song.noteAudioPath!]);
    }
  }

  /// Enregistre (ou retire, avec null) la note de départ d'un chant.
  Future<void> setSongNote(String songId, String? path) =>
      _db.from('songs').update({'note_audio_path': path}).eq('id', songId);

  Future<List<Booklet>> booklets() async {
    final rows = await Offline.rows(
        'livrets',
        () => _db
            .from('booklets')
            .select()
            .order('event_date', ascending: false, nullsFirst: false)
            .order('created_at', ascending: false));
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
    await put(bucket, path, bytes, contentType);
    return path;
  }

  /// Dépose un fichier à un chemin précis (remplace s'il existe).
  Future<void> put(String bucket, String path, Uint8List bytes, String? contentType) async {
    if (r2Buckets.contains(bucket)) {
      final type = contentType ?? 'application/octet-stream';
      final url = await _r2Url('deposer', path, type);
      _check(await http.put(Uri.parse(url), headers: {'Content-Type': type}, body: bytes));
      return;
    }
    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
  }

  /// Le fichier existe-t-il déjà ? (restauration d'une sauvegarde)
  Future<bool> exists(String bucket, String path) async {
    if (r2Buckets.contains(bucket)) return (await r2({'action': 'existe', 'path': path}))['existe'] == true;
    final slash = path.lastIndexOf('/');
    final found = await _db.storage
        .from(bucket)
        .list(path: slash < 0 ? '' : path.substring(0, slash), searchOptions: SearchOptions(search: path.substring(slash + 1)));
    return found.any((f) => f.name == path.substring(slash + 1));
  }

  Future<void> deleteFiles(String bucket, List<String> paths) async {
    if (r2Buckets.contains(bucket)) {
      await r2({'action': 'supprimer', 'paths': paths});
      return;
    }
    await _db.storage.from(bucket).remove(paths);
  }

  Future<Uint8List> download(String bucket, String path) async {
    if (r2Buckets.contains(bucket)) {
      final r = await http.get(Uri.parse(await _r2Url('lire', path)));
      _check(r);
      return r.bodyBytes;
    }
    return _db.storage.from(bucket).download(path);
  }

  /// Lien temporaire (1 h) pour lire ou télécharger un fichier privé.
  Future<String> signedUrl(String bucket, String path) => r2Buckets.contains(bucket)
      ? _r2Url('lire', path)
      : _db.storage.from(bucket).createSignedUrl(path, 3600);
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
