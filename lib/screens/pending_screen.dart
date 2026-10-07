import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PendingScreen extends StatelessWidget {
  final VoidCallback onRefresh;

  const PendingScreen({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Ton compte attend la validation du chef de chœur.\n'
                'Tu auras accès aux chants dès qu\'il sera validé.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRefresh, child: const Text('Vérifier à nouveau')),
              TextButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
