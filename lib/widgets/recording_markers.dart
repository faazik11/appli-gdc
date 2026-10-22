import 'package:flutter/material.dart';

import '../models.dart';

/// « 1:02:05 » ou « 12:30 ».
String markerClock(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Minuscules sans accents, pour chercher « priere » et trouver « Prière ».
String plainText(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString();
}

/// Chants dont le titre contient [query] (au plus [max]).
List<String> searchTitles(List<String> titles, String query, {int max = 6}) {
  final q = plainText(query.trim());
  if (q.isEmpty) return const [];
  return titles.where((t) => plainText(t).contains(q)).take(max).toList();
}

/// Demande ce qui commence à ce moment : un chant du programme en un toucher ([pinned]),
/// un autre chant en tapant le début de son titre ([all]), ou un texte libre.
Future<String?> askMarkerLabel(BuildContext context,
    {required int seconds, List<String> pinned = const [], List<String> all = const []}) {
  final text = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      void done() {
        final label = text.text.trim();
        if (label.isNotEmpty) Navigator.pop(ctx, label);
      }

      final found = searchTitles(all, text.text);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
              Text('Repère à ${markerClock(seconds)}', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(pinned.isEmpty ? 'Qu\'est-ce qui commence ici ?' : 'Au programme :'),
              const SizedBox(height: 12),
              if (pinned.isNotEmpty) ...[
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in pinned) ActionChip(label: Text(s), onPressed: () => Navigator.pop(ctx, s)),
                ]),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: text,
                autofocus: pinned.isEmpty,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: pinned.isEmpty ? 'Cherche un chant ou écris : échauffement…' : 'Un autre chant, ou : échauffement…',
                  suffixIcon: IconButton(icon: const Icon(Icons.check_rounded), onPressed: done),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => done(),
              ),
              for (final s in found)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.music_note_rounded),
                  title: Text(s),
                  onTap: () => Navigator.pop(ctx, s),
                ),
            ]),
          ),
        ),
      );
    }),
  );
}

/// Liste des repères : toucher pour aller à ce moment ; croix pour retirer (éditeurs).
class MarkerList extends StatelessWidget {
  final List<RecordingMarker> markers;
  final ValueChanged<RecordingMarker> onTap;
  final ValueChanged<RecordingMarker>? onRemove;

  const MarkerList({super.key, required this.markers, required this.onTap, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final m in markers)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 12),
          leading: Text(markerClock(m.seconds),
              style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary, fontFeatures: const [FontFeature.tabularFigures()])),
          title: Text(m.label),
          onTap: () => onTap(m),
          trailing: onRemove == null
              ? const Icon(Icons.play_arrow_rounded)
              : IconButton(
                  tooltip: 'Retirer ce repère',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => onRemove!(m),
                ),
        ),
    ]);
  }
}
