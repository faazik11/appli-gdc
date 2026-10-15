import 'package:flutter/material.dart';

import '../models.dart';

/// « 1:02:05 » ou « 12:30 ».
String markerClock(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Répartit les repères d'un enregistrement coupé en plusieurs fichiers :
/// chaque fichier reçoit les siens, comptés depuis son propre début.
List<List<RecordingMarker>> markersForParts(List<RecordingMarker> markers, List<int> partSeconds) {
  final out = <List<RecordingMarker>>[];
  var start = 0;
  for (final (i, len) in partSeconds.indexed) {
    final last = i == partSeconds.length - 1;
    out.add([
      for (final m in markers)
        if (m.seconds >= start && (last || m.seconds < start + len)) m.shift(-start),
    ]);
    start += len;
  }
  return out;
}

/// Demande ce qui commence à ce moment : un chant proposé en un toucher, ou un texte libre.
Future<String?> askMarkerLabel(BuildContext context, {required int seconds, List<String> suggestions = const []}) {
  final text = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      void done() {
        final label = text.text.trim();
        if (label.isNotEmpty) Navigator.pop(ctx, label);
      }

      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
              Text('Repère à ${markerClock(seconds)}', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('Qu\'est-ce qui commence ici ?'),
              const SizedBox(height: 12),
              if (suggestions.isNotEmpty)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in suggestions) ActionChip(label: Text(s), onPressed: () => Navigator.pop(ctx, s)),
                ]),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                autofocus: suggestions.isEmpty,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Autre : échauffement, reprise du refrain…',
                  suffixIcon: IconButton(icon: const Icon(Icons.check_rounded), onPressed: done),
                ),
                onSubmitted: (_) => done(),
              ),
            ]),
          ),
        ),
      );
    },
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
