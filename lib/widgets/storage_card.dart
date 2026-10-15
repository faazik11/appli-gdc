import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/repository.dart';
import '../theme.dart';

/// Jauges de la place occupée par les fichiers (admins, onglet Membres) :
/// Supabase (1 Go gratuit) pour le reste, Cloudflare R2 (10 Go gratuits) pour les enregistrements.
class StorageCard extends StatefulWidget {
  final Future<Map<String, int>> Function()? usage;
  final Future<int?> Function()? recordingsUsage;

  const StorageCard({super.key, this.usage, this.recordingsUsage});

  static const limitBytes = 1024 * 1024 * 1024;
  static const r2LimitBytes = 10 * limitBytes;

  static const names = {
    'enregistrements': 'Enregistrements et notes',
    'booklets': 'Livrets',
    'lyrics': 'Paroles',
    'audio': 'Audios des chants',
    'materiel': 'Photos (matériel, tenues)',
  };

  @override
  State<StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<StorageCard> {
  late final Future<Map<String, int>> _usage = (widget.usage ?? _fetch)();
  late final Future<int?> _recordings = (widget.recordingsUsage ?? _fetchR2)();

  static Future<Map<String, int>> _fetch() async {
    final data = await Supabase.instance.client.rpc('storage_usage');
    return {for (final e in (data as Map).entries) e.key as String: (e.value as num).toInt()};
  }

  /// Total chez Cloudflare R2, null si R2 n'est pas encore branché.
  static Future<int?> _fetchR2() async {
    try {
      final files = (await Repository.r2({'action': 'liste'}))['files'] as List;
      return files.fold<int>(0, (n, f) => n + ((f as Map)['size'] as num).toInt());
    } catch (_) {
      return null;
    }
  }

  Widget _gauge(ThemeData theme, String title, int used, int limit) {
    final share = used / limit;
    final high = share >= 0.7;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text('${_mb(used)} utilisés sur ${limit ~/ StorageCard.limitBytes} Go (${(share * 100).round()} %)',
          style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          minHeight: 10,
          value: share.clamp(0, 1).toDouble(),
          color: high ? AppColors.gold : theme.colorScheme.primary,
        ),
      ),
    ]);
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} Mo';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, int>>(
      future: _usage,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Card(
            child: Padding(padding: EdgeInsets.all(16), child: Text('Place occupée indisponible (connexion ?).')),
          );
        }
        if (!snap.hasData) return const Card(child: LinearProgressIndicator());
        final usage = snap.data!.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
        final used = usage.fold(0, (n, e) => n + e.value);
        final high = used / StorageCard.limitBytes >= 0.7;
        final note = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
        return Card(
          color: high ? AppColors.gold.withValues(alpha: 0.12) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _gauge(theme, 'Supabase', used, StorageCard.limitBytes),
              const SizedBox(height: 12),
              for (final e in usage)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(child: Text(StorageCard.names[e.key] ?? e.key)),
                    Text(_mb(e.value), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ]),
                ),
              if (high) ...[
                const SizedBox(height: 10),
                Text('L\'espace se remplit. Faites une sauvegarde, puis supprimez les plus vieux fichiers.', style: note),
              ],
              FutureBuilder<int?>(
                future: _recordings,
                builder: (context, r2) {
                  final bytes = r2.data;
                  if (bytes == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _gauge(theme, 'Cloudflare R2 · enregistrements et notes', bytes, StorageCard.r2LimitBytes),
                      if (bytes >= StorageCard.r2LimitBytes * 0.7) ...[
                        const SizedBox(height: 10),
                        Text('Au-delà de 10 Go, Cloudflare facture environ 0,015 \$ par Go et par mois.', style: note),
                      ],
                    ]),
                  );
                },
              ),
            ]),
          ),
        );
      },
    );
  }
}
