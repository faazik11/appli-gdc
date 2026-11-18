import 'dart:typed_data';
import 'dart:ui';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'booklet_builder.dart';
import 'file_store.dart';
import 'lyrics_layout.dart';
import 'repository.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Corrections des paroles faites dans l'appli. Le PDF d'origine n'est jamais
/// modifié : chaque enregistrement repart de lui avec toutes les corrections.
class LyricsCorrections {
  LyricsCorrections._();

  /// Polices Arial, rangées dans le stockage privé (pas dans le code public).
  static const fontPaths = ('polices/arial.ttf', 'polices/arialbd.ttf');

  /// PDF d'origine et corrections déjà enregistrées pour ce chant.
  static Future<(String, Map<String, LyricsEdit>)> load(Song song) async {
    final row = await _db.from('lyrics_corrections').select().eq('song_id', song.id).maybeSingle();
    if (row == null) return (song.lyricsPdfPath!, <String, LyricsEdit>{});
    final edits = <String, LyricsEdit>{};
    (row['edits'] as Map).forEach((k, v) {
      final m = v as Map;
      final hex = int.tryParse(m['c'] as String? ?? '', radix: 16) ?? 0;
      edits[k as String] = LyricsEdit(m['t'] as String? ?? '', Color(0xFF000000 | hex));
    });
    return (row['original_path'] as String, edits);
  }

  static Future<LyricsFonts> fonts() async {
    final store = FileStore.instance;
    final (regular, bold) = fontPaths;
    return LyricsFonts(
      await store.load(Repository.notesBucket, regular),
      await store.load(Repository.notesBucket, bold),
    );
  }

  static String _hex(Color c) => [c.r, c.g, c.b].map((v) => (v * 255).round().toRadixString(16).padLeft(2, '0')).join();

  /// Enregistre le PDF corrigé, puis refait les livrets qui contiennent ce chant.
  /// Renvoie le chemin du nouveau PDF.
  static Future<String> save({
    required Song song,
    required String originalPath,
    required Map<String, LyricsEdit> edits,
    required Uint8List pdf,
    void Function(String step)? onProgress,
  }) async {
    final repo = Repository.instance;
    onProgress?.call('Enregistrement du PDF…');
    final path = await repo.upload(Repository.lyricsBucket, '${song.title}_corrige.pdf', pdf, 'application/pdf');
    await FileStore.instance.keep(Repository.lyricsBucket, path, pdf);
    await _db.from('lyrics_corrections').upsert({
      'song_id': song.id,
      'original_path': originalPath,
      'edits': {
        for (final e in edits.entries) e.key: {'t': e.value.text, 'c': _hex(e.value.color)},
      },
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _db.from('songs').update({'lyrics_pdf_path': path}).eq('id', song.id);
    // L'ancienne version corrigée ne sert plus (l'original, lui, est gardé).
    final previous = song.lyricsPdfPath;
    if (previous != null && previous != originalPath && previous != path) {
      try {
        await repo.deleteFiles(Repository.lyricsBucket, [previous]);
      } catch (_) {}
    }
    await _rebuildBooklets(song.id, onProgress);
    return path;
  }

  /// Un nouveau PDF a été déposé à la main : les anciennes corrections ne s'y appliquent plus.
  static Future<void> forget(String songId) => _db.from('lyrics_corrections').delete().eq('song_id', songId);

  static Future<void> _rebuildBooklets(String songId, void Function(String step)? onProgress) async {
    final repo = Repository.instance;
    final booklets = (await repo.booklets())
        .where((b) => b.pdfPath != null && b.parts.any((p) => p.songIds.contains(songId)))
        .toList();
    if (booklets.isEmpty) return;
    final songsById = {for (final s in await repo.songs()) s.id: s};
    for (final b in booklets) {
      onProgress?.call('Mise à jour du livret « ${b.title} »…');
      final bytes = await BookletBuilder((path) => repo.download(Repository.lyricsBucket, path)).build(
        title: b.title,
        eventDate: b.eventDate,
        parts: b.parts,
        songsById: songsById,
      );
      final path = await repo.upload(Repository.bookletsBucket, '${b.title}.pdf', Uint8List.fromList(bytes), 'application/pdf');
      await repo.saveBooklet(id: b.id, title: b.title, eventDate: b.eventDate, parts: b.parts, pdfPath: path);
      try {
        await repo.deleteFiles(Repository.bookletsBucket, [b.pdfPath!]);
      } catch (_) {}
    }
  }
}
