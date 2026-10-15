import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

/// Jauge de la place occupée par les fichiers (admins, onglet Membres).
/// L'offre gratuite de Supabase donne 1 Go ; les enregistrements de répète sont les plus lourds.
class StorageCard extends StatefulWidget {
  final Future<Map<String, int>> Function()? usage;

  const StorageCard({super.key, this.usage});

  static const limitBytes = 1024 * 1024 * 1024;

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

  static Future<Map<String, int>> _fetch() async {
    final data = await Supabase.instance.client.rpc('storage_usage');
    return {for (final e in (data as Map).entries) e.key as String: (e.value as num).toInt()};
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
        final share = used / StorageCard.limitBytes;
        final high = share >= 0.7;
        return Card(
          color: high ? AppColors.gold.withValues(alpha: 0.12) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_mb(used)} utilisés sur 1 Go (${(share * 100).round()} %)', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: share.clamp(0, 1).toDouble(),
                  color: high ? AppColors.gold : theme.colorScheme.primary,
                ),
              ),
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
                Text(
                  'L\'espace se remplit. Faites une sauvegarde, puis supprimez les plus vieux enregistrements de répète.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}
