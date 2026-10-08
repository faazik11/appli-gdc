import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/ui.dart';

class PendingScreen extends StatelessWidget {
  final VoidCallback onRefresh;

  const PendingScreen({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const AppLogo(size: 64),
                    const SizedBox(height: 20),
                    Text('Bienvenue !', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 10),
                    Text(
                      'Ton compte attend la validation du chef de chœur. '
                      'Tu auras accès aux chants dès qu\'il sera validé.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: onRefresh,
                      label: const Text('Vérifier à nouveau'),
                    ),
                    TextButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      child: const Text('Se déconnecter'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
