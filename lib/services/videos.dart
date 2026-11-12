import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform/video_files.dart';
import 'offline.dart';
import 'repository.dart';

/// Vidéo d'une prestation ; le fichier est chez Cloudflare R2 (dossier videos/).
class Video {
  final String id;
  final String title;
  final String? eventId;
  final DateTime? filmedOn;
  final String path;
  final String? contentType;
  final int? sizeBytes;
  final int? durationSeconds;
  final String? notes;
  final DateTime createdAt;

  const Video({
    required this.id,
    required this.title,
    required this.path,
    required this.createdAt,
    this.eventId,
    this.filmedOn,
    this.contentType,
    this.sizeBytes,
    this.durationSeconds,
    this.notes,
  });

  /// Date affichée : celle du tournage, sinon celle de l'ajout.
  DateTime get date => filmedOn ?? createdAt;

  factory Video.fromMap(Map<String, dynamic> m) => Video(
        id: m['id'] as String,
        title: m['title'] as String,
        eventId: m['event_id'] as String?,
        filmedOn: m['filmed_on'] == null ? null : DateTime.parse(m['filmed_on'] as String),
        path: m['path'] as String,
        contentType: m['content_type'] as String?,
        sizeBytes: (m['size_bytes'] as num?)?.toInt(),
        durationSeconds: (m['duration_seconds'] as num?)?.toInt(),
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// « 1,2 Go », « 350 Mo »
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Go';
  }
  return '${(bytes / (1024 * 1024)).round()} Mo';
}

String videoContentType(String name, String type) {
  if (type.isNotEmpty) return type;
  final ext = name.contains('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';
  return switch (ext) {
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'm4v' => 'video/x-m4v',
    _ => 'video/mp4',
  };
}

class Videos {
  Videos._();

  static SupabaseClient get _db => Supabase.instance.client;
  static const _bucket = Repository.notesBucket;

  static String? _clean(String? s) => (s?.trim().isEmpty ?? true) ? null : s!.trim();
  static String? _day(DateTime? d) => d?.toIso8601String().substring(0, 10);

  static Future<List<Video>> list() async {
    final rows = await Offline.rows(
        'videos',
        () => _db
            .from('videos')
            .select()
            .order('filmed_on', ascending: false, nullsFirst: false)
            .order('created_at', ascending: false));
    return rows.map(Video.fromMap).toList();
  }

  /// Message en français renvoyé par la fonction « fichiers » (ex. plus de place).
  static Future<Map<String, dynamic>> _r2(Map<String, dynamic> body) async {
    try {
      return await Repository.r2(body);
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is String) throw FormatException(details['error'] as String);
      rethrow;
    }
  }

  /// Place occupée et limite chez Cloudflare R2.
  static Future<({int used, int limit})> space() async {
    final r = await _r2({'action': 'place'});
    return (used: (r['used'] as num).toInt(), limit: (r['limit'] as num).toInt());
  }

  static Future<void> add({
    required PickedVideo file,
    required String title,
    String? eventId,
    DateTime? filmedOn,
    String? notes,
    required void Function(double) onProgress,
  }) async {
    final type = videoContentType(file.name, file.type);
    final safe = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = 'videos/${DateTime.now().millisecondsSinceEpoch}_$safe';
    final url = (await _r2({'action': 'deposer', 'path': path, 'type': type, 'size': file.size}))['url'] as String;
    await uploadVideo(file, url, type, onProgress);
    try {
      await _db.from('videos').insert({
        'title': title.trim(),
        'event_id': eventId,
        'filmed_on': _day(filmedOn),
        'path': path,
        'content_type': type,
        'size_bytes': file.size,
        'duration_seconds': file.seconds > 0 ? file.seconds : null,
        'notes': _clean(notes),
      });
    } catch (_) {
      await Repository.instance.deleteFiles(_bucket, [path]).catchError((_) {});
      rethrow;
    }
  }

  static Future<void> update(Video v, {required String title, String? eventId, DateTime? filmedOn, String? notes}) =>
      _db.from('videos').update({
        'title': title.trim(),
        'event_id': eventId,
        'filmed_on': _day(filmedOn),
        'notes': _clean(notes),
      }).eq('id', v.id);

  static Future<void> delete(Video v) async {
    await _db.from('videos').delete().eq('id', v.id);
    await Repository.instance.deleteFiles(_bucket, [v.path]);
  }

  static Future<String> url(Video v) => Repository.instance.signedUrl(_bucket, v.path);
}
