import 'package:flutter/material.dart';

import '../platform/install_info.dart';
import '../theme.dart';

/// Explique comment mettre l'appli sur l'écran d'accueil (affiché seulement dans le navigateur).
class InstallCard extends StatefulWidget {
  const InstallCard({super.key});

  @override
  State<InstallCard> createState() => _InstallCardState();
}

class _InstallCardState extends State<InstallCard> {
  bool _hidden = false;

  void _howTo() {
    final ios = isIos;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Installer l\'appli', style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 12),
            for (final (i, step) in (ios
                    ? [
                        'Ouvre ce site dans Safari.',
                        'Touche le bouton Partager (le carré avec une flèche vers le haut).',
                        'Choisis « Sur l\'écran d\'accueil », puis « Ajouter ».',
                      ]
                    : [
                        'Ouvre ce site dans Chrome.',
                        'Touche le menu ⋮ en haut à droite.',
                        'Choisis « Installer l\'application » ou « Ajouter à l\'écran d\'accueil ».',
                      ])
                .indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.aubergine,
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(step)),
                ]),
              ),
            const SizedBox(height: 4),
            const Text('L\'icône GDC apparaît alors sur ton téléphone et ouvre l\'appli en plein écran.'),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isInstalledApp || _hidden) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network('icons/Icon-192.png', width: 42, height: 42, errorBuilder: (_, __, ___) => const Icon(Icons.install_mobile_rounded)),
          ),
          title: const Text('Mets l\'appli sur ton téléphone'),
          subtitle: const Text('Une icône GDC sur l\'écran d\'accueil, comme une vraie appli'),
          onTap: _howTo,
          trailing: IconButton(
            tooltip: 'Masquer',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() => _hidden = true),
          ),
        ),
      ),
    );
  }
}
