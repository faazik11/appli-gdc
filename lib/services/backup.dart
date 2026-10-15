import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository.dart';

/// Avancement affiché pendant une sauvegarde ou une restauration.
typedef BackupProgress = void Function(String step, double fraction);

/// Résultat d'une restauration : lignes remises par table, fichiers remis ou déjà présents.
class RestoreReport {
  final Map<String, int> rows;
  final int filesAdded;
  final int filesKept;
  final List<String> filesFailed;

  RestoreReport(this.rows, this.filesAdded, this.filesKept, this.filesFailed);

  int get rowsAdded => rows.values.fold(0, (a, b) => a + b);
}

/// Sauvegarde complète de l'appli dans un fichier .zip (données + fichiers),
/// et restauration depuis ce fichier. Réservé aux admins.
class Backup {
  final Future<Map<String, dynamic>> Function() export;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data) restoreRows;
  final Future<Uint8List> Function(String bucket, String path) download;

  /// Dépose un fichier s'il n'existe pas déjà ; renvoie false s'il était déjà là.
  final Future<bool> Function(String bucket, String path, Uint8List bytes, String? type) uploadIfMissing;

  Backup({required this.export, required this.restoreRows, required this.download, required this.uploadIfMissing});

  factory Backup.supabase() {
    final db = Supabase.instance.client;
    final repo = Repository.instance;
    return Backup(
      export: () async {
        final data = Map<String, dynamic>.from(await db.rpc('backup_export') as Map);
        // Les enregistrements sont chez Cloudflare R2 : la liste vient de là-bas.
        final r2 = (await Repository.r2({'action': 'liste'}))['files'] as List;
        data['files'] = [
          for (final f in (data['files'] as List? ?? const []))
            if (!Repository.r2Buckets.contains((f as Map)['bucket'])) f,
          for (final f in r2)
            {'bucket': Repository.notesBucket, 'path': (f as Map)['path'], 'type': null, 'size': '${f['size']}'},
        ];
        return data;
      },
      restoreRows: (data) async => Map<String, dynamic>.from(await db.rpc('backup_restore', params: {'data': data}) as Map),
      download: repo.download,
      uploadIfMissing: (bucket, path, bytes, type) async {
        if (Repository.r2Buckets.contains(bucket)) {
          if (await repo.exists(bucket, path)) return false;
          await repo.put(bucket, path, bytes, type);
          return true;
        }
        try {
          await db.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: type, upsert: false));
          return true;
        } on StorageException catch (e) {
          final msg = e.message.toLowerCase();
          if (e.statusCode == '409' || msg.contains('exists') || msg.contains('duplicate')) return false;
          rethrow;
        }
      },
    );
  }

  static const dataFile = 'donnees.json';
  static const filesDir = 'fichiers';

  static String fileName(DateTime when) => 'sauvegarde-gdc-${when.year}-${_two(when.month)}-${_two(when.day)}.zip';

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 12/10/2026
  static String day(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  /// Fabrique le .zip ; les fichiers impossibles à télécharger sont listés dans le LISEZ-MOI.
  Future<Uint8List> create({BackupProgress? onProgress}) async {
    onProgress?.call('Lecture des données…', 0);
    final data = await export();
    final files = [for (final f in (data['files'] as List? ?? const [])) Map<String, dynamic>.from(f as Map)];
    final archive = Archive();
    final missing = <String>[];
    for (var i = 0; i < files.length; i++) {
      final bucket = files[i]['bucket'] as String;
      final path = files[i]['path'] as String;
      onProgress?.call('Fichier ${i + 1} sur ${files.length}…', (i + 1) / (files.length + 1));
      try {
        final file = ArchiveFile.bytes('$filesDir/$bucket/$path', await download(bucket, path))
          // PDF, photos et sons sont déjà compressés : on les range tels quels (plus rapide)
          ..compression = CompressionType.none;
        archive.add(file);
      } catch (_) {
        missing.add('$bucket/$path');
      }
    }
    archive.add(ArchiveFile.string(dataFile, const JsonEncoder.withIndent(' ').convert(data)));
    archive.add(ArchiveFile.string('LISEZ-MOI.txt', _readme(data, files.length - missing.length, missing)));
    onProgress?.call('Fabrication du fichier…', 1);
    return ZipEncoder().encodeBytes(archive);
  }

  /// Remet ce qui manque depuis un .zip de sauvegarde, sans rien effacer ni remplacer.
  Future<RestoreReport> restore(Uint8List zip, {BackupProgress? onProgress}) async {
    onProgress?.call('Ouverture de la sauvegarde…', 0);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zip);
    } catch (_) {
      throw const FormatException("Ce fichier n'est pas une sauvegarde de l'appli GDC.");
    }
    final json = archive.find(dataFile)?.readBytes();
    if (json == null) throw const FormatException("Ce fichier n'est pas une sauvegarde de l'appli GDC.");
    final data = Map<String, dynamic>.from(jsonDecode(utf8.decode(json)) as Map);

    onProgress?.call('Remise des données…', 0);
    final added = await restoreRows(data);
    final rows = {for (final e in added.entries) e.key: (e.value as num).toInt()};

    final types = {
      for (final f in (data['files'] as List? ?? const []))
        '${(f as Map)['bucket']}/${f['path']}': f['type'] as String?,
    };
    final entries = archive.files.where((f) => f.isFile && f.name.startsWith('$filesDir/')).toList();
    var filesAdded = 0, filesKept = 0;
    final failed = <String>[];
    for (var i = 0; i < entries.length; i++) {
      onProgress?.call('Fichier ${i + 1} sur ${entries.length}…', (i + 1) / entries.length);
      final key = entries[i].name.substring(filesDir.length + 1);
      final slash = key.indexOf('/');
      if (slash <= 0) continue;
      try {
        final put = await uploadIfMissing(key.substring(0, slash), key.substring(slash + 1), entries[i].readBytes()!, types[key]);
        put ? filesAdded++ : filesKept++;
      } catch (_) {
        failed.add(key);
      }
    }
    return RestoreReport(rows, filesAdded, filesKept, failed);
  }

  static String _readme(Map<String, dynamic> data, int fileCount, List<String> missing) {
    final tables = Map<String, dynamic>.from(data['tables'] as Map? ?? const {});
    final when = DateTime.tryParse('${data['created_at']}')?.toLocal() ?? DateTime.now();
    final b = StringBuffer()
      ..writeln('Sauvegarde de l\'appli du Groupe de Chant Narbonne')
      ..writeln('Faite le ${day(when)} à ${_two(when.hour)}h${_two(when.minute)}')
      ..writeln()
      ..writeln('Contenu :')
      ..writeln('- donnees.json : toutes les fiches (chants, livrets, agenda, réponses, présences,')
      ..writeln('  annonces, inventaire, tenues, enregistrements, membres et leurs adresses e-mail).')
      ..writeln('- fichiers/ : les PDF de paroles, les livrets, les sons, les photos du matériel')
      ..writeln('  et des tenues, les enregistrements des répétitions ($fileCount fichiers).')
      ..writeln()
      ..writeln('Pour restaurer : dans l\'appli, onglet Membres > Sauvegarde > « Restaurer »,')
      ..writeln('puis choisir ce fichier .zip (sans le décompresser). La restauration remet ce qui')
      ..writeln('manque et ne supprime ni ne remplace rien.')
      ..writeln()
      ..writeln('Gardez ce fichier en lieu sûr : il contient les e-mails des membres.')
      ..writeln()
      ..writeln('Nombre de fiches :');
    for (final e in tables.entries) {
      b.writeln('- ${e.key} : ${(e.value as List).length}');
    }
    if (missing.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Fichiers qui n\'ont pas pu être copiés :');
      for (final m in missing) {
        b.writeln('- $m');
      }
    }
    return b.toString();
  }
}
