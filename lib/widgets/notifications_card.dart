import 'package:flutter/material.dart';

import '../services/push_service.dart';

/// Propose d'activer les notifications (rappels de répétitions, prestations, annonces).
class NotificationsCard extends StatefulWidget {
  const NotificationsCard({super.key});

  @override
  State<NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<NotificationsCard> {
  bool _hidden = false;
  bool _busy = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await PushService.enable();
      messenger.showSnackBar(SnackBar(
        content: Text(switch (result) {
          PushState.on => 'Notifications activées.',
          PushState.blocked => 'Notifications refusées. Tu peux les autoriser dans les réglages du téléphone.',
          _ => 'Notifications pas activées.',
        }),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Impossible d\'activer les notifications : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PushState>(
      valueListenable: PushService.state,
      builder: (context, state, _) {
        if (state != PushState.off || _hidden) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
              leading: const Icon(Icons.notifications_active_rounded, size: 32),
              title: const Text('Activer les notifications'),
              subtitle: const Text('Rappel la veille des répétitions et prestations, nouvelles annonces'),
              onTap: _busy ? null : _enable,
              trailing: IconButton(
                tooltip: 'Plus tard',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _hidden = true),
              ),
            ),
          ),
        );
      },
    );
  }
}
