import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../platform/device_files.dart';
import 'file_store.dart';
import 'offline.dart';
import 'repository.dart';

/// Inventaire du local et enregistrements des répétitions.
abstract class WorkBackend {
  static const photosBucket = 'materiel';
  static const recordingsBucket = 'enregistrements';

  Future<List<EquipmentCategory>> equipmentCategories();
  Future<EquipmentCategory> addEquipmentCategory(String name);
  Future<void> renameEquipmentCategory(String id, String name);
  Future<void> deleteEquipmentCategory(String id);
  Future<List<EquipmentItem>> equipment();
  Future<void> saveEquipment({
    String? id,
    required String name,
    String? categoryId,
    required int quantity,
    String? notes,
    String? photoPath,
  });
  Future<void> deleteEquipment(EquipmentItem item);

  /// Matériel à emporter pour un événement.
  Future<List<EventGear>> eventGear(String eventId);

  /// Remplace la liste (matériel → quantité) en gardant ce qui était déjà coché.
  Future<void> setEventGear(String eventId, Map<String, int> quantities);
  Future<void> setGearPacked(String eventId, String equipmentId, bool packed);

  /// Tenues réutilisables et tenue du jour d'un événement.
  Future<List<Outfit>> outfits();
  Future<void> saveOutfit({String? id, required String name, String? notes, String? photoPath, required List<OutfitItem> items});
  Future<void> deleteOutfit(Outfit outfit);
  Future<void> setEventOutfit(String eventId, String? outfitId);

  /// Liste des vêtements dans laquelle on choisit les éléments des tenues.
  Future<List<Garment>> garments();
  Future<Garment> saveGarment({String? id, required String name, String? photoPath});

  /// Retire aussi le vêtement des tenues qui l'utilisent.
  Future<void> deleteGarment(Garment garment);

  Future<List<Recording>> recordings();
  Future<void> saveRecording({
    required DateTime recordedAt,
    String? eventId,
    String? title,
    String? notes,
    required String audioPath,
    int? durationSeconds,
  });
  Future<void> updateRecording(String id, {String? title, String? notes});
  Future<void> deleteRecording(Recording r);

  /// Dépose un fichier et renvoie son chemin.
  Future<String> upload(String bucket, String fileName, Uint8List bytes, String contentType);
  Future<void> deleteFile(String bucket, String path);

  /// Adresse pour écouter un enregistrement (copie du téléphone si elle existe).
  Future<String> audioUrl(String path);
}

class SupabaseWork implements WorkBackend {
  SupabaseClient get _db => Supabase.instance.client;
  final _repo = Repository.instance;

  String? _clean(String? s) => (s?.trim().isEmpty ?? true) ? null : s!.trim();

  @override
  Future<List<EquipmentCategory>> equipmentCategories() async {
    final rows = await Offline.rows('categories-materiel', () => _db.from('equipment_categories').select().order('name'));
    return rows.map(EquipmentCategory.fromMap).toList();
  }

  @override
  Future<EquipmentCategory> addEquipmentCategory(String name) async {
    final row = await _db.from('equipment_categories').insert({'name': name.trim()}).select().single();
    return EquipmentCategory.fromMap(row);
  }

  @override
  Future<void> renameEquipmentCategory(String id, String name) =>
      _db.from('equipment_categories').update({'name': name.trim()}).eq('id', id);

  @override
  Future<void> deleteEquipmentCategory(String id) => _db.from('equipment_categories').delete().eq('id', id);

  @override
  Future<List<EquipmentItem>> equipment() async {
    final rows = await Offline.rows('materiel', () => _db.from('equipment').select().order('name'));
    return rows.map(EquipmentItem.fromMap).toList();
  }

  @override
  Future<void> saveEquipment({
    String? id,
    required String name,
    String? categoryId,
    required int quantity,
    String? notes,
    String? photoPath,
  }) async {
    final data = {
      'name': name.trim(),
      'category_id': categoryId,
      'quantity': quantity,
      'notes': _clean(notes),
      'photo_path': photoPath,
    };
    if (id == null) {
      await _db.from('equipment').insert(data);
    } else {
      await _db.from('equipment').update(data).eq('id', id);
    }
  }

  @override
  Future<void> deleteEquipment(EquipmentItem item) async {
    await _db.from('equipment').delete().eq('id', item.id);
    if (item.photoPath != null) await _repo.deleteFiles(WorkBackend.photosBucket, [item.photoPath!]);
  }

  @override
  Future<List<EventGear>> eventGear(String eventId) async {
    final rows = await Offline.rows(
        'materiel-evenement-$eventId', () => _db.from('event_equipment').select().eq('event_id', eventId));
    return rows.map(EventGear.fromMap).toList();
  }

  @override
  Future<void> setEventGear(String eventId, Map<String, int> quantities) async {
    final current = await _db.from('event_equipment').select('equipment_id').eq('event_id', eventId);
    final removed = [
      for (final r in current)
        if (!quantities.containsKey(r['equipment_id'])) r['equipment_id'] as String,
    ];
    if (removed.isNotEmpty) {
      await _db.from('event_equipment').delete().eq('event_id', eventId).inFilter('equipment_id', removed);
    }
    if (quantities.isNotEmpty) {
      await _db.from('event_equipment').upsert(
        [for (final e in quantities.entries) {'event_id': eventId, 'equipment_id': e.key, 'quantity': e.value}],
        onConflict: 'event_id,equipment_id',
      );
    }
  }

  @override
  Future<void> setGearPacked(String eventId, String equipmentId, bool packed) => _db
      .from('event_equipment')
      .update({'packed': packed})
      .eq('event_id', eventId)
      .eq('equipment_id', equipmentId);

  @override
  Future<List<Outfit>> outfits() async {
    final rows = await Offline.rows('tenues', () => _db.from('outfits').select('*, outfit_items(*, garments(*))').order('name'));
    return rows.map(Outfit.fromMap).toList();
  }

  @override
  Future<void> saveOutfit(
      {String? id, required String name, String? notes, String? photoPath, required List<OutfitItem> items}) async {
    final data = {'name': name.trim(), 'notes': _clean(notes), 'photo_path': photoPath};
    final outfitId = id == null
        ? (await _db.from('outfits').insert(data).select('id').single())['id'] as String
        : (await _db.from('outfits').update(data).eq('id', id).select('id').single())['id'] as String;
    await _db.from('outfit_items').delete().eq('outfit_id', outfitId);
    if (items.isNotEmpty) {
      await _db.from('outfit_items').insert([
        for (final (i, item) in items.indexed)
          {
            'outfit_id': outfitId,
            'garment_id': item.garmentId,
            'label': item.label.trim(),
            'photo_path': item.garmentId == null ? item.photoPath : null,
            'position': i,
          },
      ]);
    }
  }

  @override
  Future<void> deleteOutfit(Outfit outfit) async {
    await _db.from('outfits').delete().eq('id', outfit.id);
    // Les photos des vêtements restent : elles appartiennent à la liste des vêtements.
    final photos = [outfit.photoPath, for (final i in outfit.items.where((i) => i.garmentId == null)) i.photoPath]
        .whereType<String>()
        .toList();
    if (photos.isNotEmpty) await _repo.deleteFiles(WorkBackend.photosBucket, photos);
  }

  @override
  Future<void> setEventOutfit(String eventId, String? outfitId) =>
      _db.from('events').update({'outfit_id': outfitId}).eq('id', eventId);

  @override
  Future<List<Garment>> garments() async {
    final rows = await Offline.rows('vetements', () => _db.from('garments').select().order('name'));
    return rows.map(Garment.fromMap).toList();
  }

  @override
  Future<Garment> saveGarment({String? id, required String name, String? photoPath}) async {
    final data = {'name': name.trim(), 'photo_path': photoPath};
    final row = id == null
        ? await _db.from('garments').insert(data).select().single()
        : await _db.from('garments').update(data).eq('id', id).select().single();
    return Garment.fromMap(row);
  }

  @override
  Future<void> deleteGarment(Garment garment) async {
    await _db.from('garments').delete().eq('id', garment.id);
    if (garment.photoPath != null) await _repo.deleteFiles(WorkBackend.photosBucket, [garment.photoPath!]);
  }

  @override
  Future<List<Recording>> recordings() async {
    final rows = await Offline.rows(
        'enregistrements', () => _db.from('recordings').select().order('recorded_at', ascending: false));
    return rows.map(Recording.fromMap).toList();
  }

  @override
  Future<void> saveRecording({
    required DateTime recordedAt,
    String? eventId,
    String? title,
    String? notes,
    required String audioPath,
    int? durationSeconds,
  }) =>
      _db.from('recordings').insert({
        'recorded_at': recordedAt.toUtc().toIso8601String(),
        'event_id': eventId,
        'title': _clean(title),
        'notes': _clean(notes),
        'audio_path': audioPath,
        'duration_seconds': durationSeconds,
      });

  @override
  Future<void> updateRecording(String id, {String? title, String? notes}) =>
      _db.from('recordings').update({'title': _clean(title), 'notes': _clean(notes)}).eq('id', id);

  @override
  Future<void> deleteRecording(Recording r) async {
    await _db.from('recordings').delete().eq('id', r.id);
    await _repo.deleteFiles(WorkBackend.recordingsBucket, [r.audioPath]);
  }

  @override
  Future<String> upload(String bucket, String fileName, Uint8List bytes, String contentType) =>
      _repo.upload(bucket, fileName, bytes, contentType);

  @override
  Future<void> deleteFile(String bucket, String path) => _repo.deleteFiles(bucket, [path]);

  @override
  Future<String> audioUrl(String path) async {
    const bucket = WorkBackend.recordingsBucket;
    final type = path.endsWith('.m4a') ? 'audio/mp4' : (path.endsWith('.ogg') ? 'audio/ogg' : 'audio/webm');
    if (await FileStore.instance.has(bucket, path)) {
      final local = await localUrl(await FileStore.instance.load(bucket, path), type);
      if (local != null) return local;
    }
    try {
      // En ligne : lecture immédiate, et copie gardée en arrière-plan pour l'écouter hors connexion.
      final url = await _repo.signedUrl(bucket, path);
      FileStore.instance.load(bucket, path).ignore();
      return url;
    } catch (_) {
      final local = await localUrl(await FileStore.instance.load(bucket, path), type);
      if (local == null) rethrow;
      return local;
    }
  }
}

/// Enregistrement terminé mais pas encore envoyé (pas de réseau, envoi interrompu).
/// Le fichier reste sur le téléphone jusqu'à ce qu'il soit bien en ligne : rien n'est perdu.
class PendingRecording {
  final String key;
  final DateTime recordedAt;
  final String? eventId;
  final String? title;
  final String? notes;
  final String mimeType;
  final int durationSeconds;

  const PendingRecording({
    required this.key,
    required this.recordedAt,
    this.eventId,
    this.title,
    this.notes,
    required this.mimeType,
    required this.durationSeconds,
  });

  Map<String, dynamic> toMap() => {
        'key': key,
        'recordedAt': recordedAt.toIso8601String(),
        'eventId': eventId,
        'title': title,
        'notes': notes,
        'mimeType': mimeType,
        'duration': durationSeconds,
      };

  factory PendingRecording.fromMap(Map<String, dynamic> m) => PendingRecording(
        key: m['key'] as String,
        recordedAt: DateTime.parse(m['recordedAt'] as String),
        eventId: m['eventId'] as String?,
        title: m['title'] as String?,
        notes: m['notes'] as String?,
        mimeType: m['mimeType'] as String,
        durationSeconds: (m['duration'] as num).toInt(),
      );

  String get extension => mimeType.contains('mp4') ? 'm4a' : (mimeType.contains('ogg') ? 'ogg' : 'webm');
  String get contentType => mimeType.split(';').first;
}

class PendingRecordings {
  static const _indexKey = 'enregistrements-en-attente';

  static Future<List<PendingRecording>> list() async {
    final raw = await deviceGet(_indexKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(utf8.decode(raw)) as List)
          .map((e) => PendingRecording.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<PendingRecording> items) =>
      devicePut(_indexKey, Uint8List.fromList(utf8.encode(jsonEncode([for (final p in items) p.toMap()]))));

  /// Garde l'enregistrement sur le téléphone avant toute tentative d'envoi.
  static Future<PendingRecording> keep(Uint8List bytes, PendingRecording info) async {
    await devicePut(info.key, bytes);
    await _save([...await list(), info]);
    return info;
  }

  /// Envoie un enregistrement gardé ; il n'est retiré du téléphone qu'une fois bien en ligne.
  static Future<void> send(WorkBackend backend, PendingRecording p) async {
    final bytes = await deviceGet(p.key);
    if (bytes == null) {
      await _save((await list()).where((e) => e.key != p.key).toList());
      return;
    }
    final stamp = '${p.recordedAt.year}-${p.recordedAt.month.toString().padLeft(2, '0')}-${p.recordedAt.day.toString().padLeft(2, '0')}';
    final path = await backend.upload(WorkBackend.recordingsBucket, 'repetition_$stamp.${p.extension}', bytes, p.contentType);
    await backend.saveRecording(
      recordedAt: p.recordedAt,
      eventId: p.eventId,
      title: p.title,
      notes: p.notes,
      audioPath: path,
      durationSeconds: p.durationSeconds,
    );
    // Déjà sur le téléphone : réécoute immédiate sans retéléchargement.
    await FileStore.instance.keep(WorkBackend.recordingsBucket, path, bytes);
    await _save((await list()).where((e) => e.key != p.key).toList());
    await deviceDelete(p.key);
  }

  static Future<void> discard(PendingRecording p) async {
    await _save((await list()).where((e) => e.key != p.key).toList());
    await deviceDelete(p.key);
  }
}
