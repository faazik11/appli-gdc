import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform/device_files.dart';
import '../platform/pick_file.dart';
import '../services/backup.dart';
import '../services/errors.dart';
import '../theme.dart';

/// Sauvegarde complète à garder sur l'ordinateur, et restauration (admins, onglet Membres).
class BackupCard extends StatefulWidget {
  final Backup? backup;
  final Future<DateTime?> Function()? lastBackup;

  const BackupCard({super.key, this.backup, this.lastBackup});

  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  late final Backup _backup = widget.backup ?? Backup.supabase();
  late Future<DateTime?> _last = _fetchLast();

  Future<DateTime?> _fetchLast() async {
    if (widget.lastBackup != null) return widget.lastBackup!();
    try {
      final rows = await Supabase.instance.client
          .from('backups')
          .select('created_at')
          .order('created_at', ascending: false)
          .limit(1);
      return rows.isEmpty ? null : DateTime.parse(rows.first['created_at'] as String).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Fenêtre d'attente avec l'étape en cours ; renvoie le résultat de [work].
  Future<T?> _withProgress<T>(String title, Future<T> Function(BackupProgress onProgress) work) async {
    final step = ValueNotifier<(String, double)>(('Préparation…', 0));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder(
            valueListenable: step,
            builder: (context, s, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              LinearProgressIndicator(value: s.$2 > 0 ? s.$2 : null),
              const SizedBox(height: 12),
              Text(s.$1),
              const SizedBox(height: 4),
              Text("Gardez l'appli ouverte jusqu'à la fin.",
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
    Object? error;
    T? result;
    try {
      result = await work((text, fraction) => step.value = (text, fraction));
    } catch (e) {
      error = e;
    }
    if (!mounted) return null;
    Navigator.of(context, rootNavigator: true).pop();
    if (error != null) {
      await _message('Ça n\'a pas marché',
          error is FormatException ? error.message : explain(error));
    }
    return result;
  }

  Future<void> _message(String title, String text) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );

  Future<void> _create() async {
    Uint8List? zip;
    await _withProgress('Sauvegarde en cours', (onProgress) async {
      zip = await _backup.create(onProgress: onProgress);
    });
    if (zip == null || !mounted) return;
    setState(() => _last = _fetchLast());
    final name = Backup.fileName(DateTime.now());
    final size = (zip!.length / (1024 * 1024)).toStringAsFixed(zip!.length < 10 * 1024 * 1024 ? 1 : 0);
    // Un vrai appui est nécessaire pour enregistrer le fichier (surtout sur iPhone)
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sauvegarde prête'),
        content: Text('$name · $size Mo\n\n'
            'Enregistrez-la sur votre ordinateur (ou dans Fichiers / iCloud Drive sur iPhone), '
            'de préférence à un endroit lui-même sauvegardé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
          FilledButton.icon(
            icon: const Icon(Icons.download_rounded),
            label: const Text('Enregistrer le fichier'),
            onPressed: () async {
              if (await saveToDevice(zip!, name, 'application/zip') && context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurer une sauvegarde'),
        content: const Text('Choisissez un fichier sauvegarde-gdc-….zip (sans le décompresser).\n\n'
            'Tout ce qui manque dans l\'appli sera remis : chants, livrets, agenda, annonces, '
            'inventaire, tenues, enregistrements et leurs fichiers. Rien n\'est supprimé ni remplacé, '
            'et aucune notification n\'est envoyée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Choisir le fichier')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final file = await pickOneFile(type: FileType.custom, extensions: ['zip']);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    final report = await _withProgress('Restauration en cours', (onProgress) => _backup.restore(bytes, onProgress: onProgress));
    if (report == null || !mounted) return;
    final lines = [
      report.rowsAdded == 0 ? 'Aucune fiche ne manquait.' : '${report.rowsAdded} fiches remises.',
      report.filesAdded == 0 ? 'Aucun fichier ne manquait.' : '${report.filesAdded} fichiers remis.',
      if (report.filesKept > 0) '${report.filesKept} fichiers étaient déjà là.',
      if (report.filesFailed.isNotEmpty) '${report.filesFailed.length} fichiers n\'ont pas pu être remis.',
    ];
    await _message('Restauration terminée', lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<DateTime?>(
      future: _last,
      builder: (context, snap) {
        final last = snap.data;
        final overdue = snap.connectionState == ConnectionState.done &&
            (last == null || DateTime.now().difference(last).inDays >= 30);
        final when = last == null
            ? 'Aucune sauvegarde pour l\'instant'
            : 'Dernière sauvegarde le ${Backup.day(last)}';
        return Card(
          color: overdue ? AppColors.gold.withValues(alpha: 0.12) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(overdue ? Icons.warning_amber_rounded : Icons.verified_rounded,
                    color: overdue ? AppColors.gold : theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(when, style: theme.textTheme.titleMedium)),
              ]),
              const SizedBox(height: 8),
              Text(
                'Une copie complète de l\'appli (chants, livrets, agenda, présences, inventaire, tenues, '
                'enregistrements et tous les fichiers) dans un seul fichier à garder sur votre ordinateur. '
                'Conseil : une fois par mois, et avant tout gros changement.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Faire une sauvegarde'),
                ),
                TextButton.icon(
                  onPressed: _restore,
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: const Text('Restaurer'),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }
}
