import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/pending_screen.dart';
import 'services/repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const AppliGdc());
}

class AppliGdc extends StatelessWidget {
  const AppliGdc({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Appli GDC',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6A3D9A)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Affiche la connexion, l'attente de validation ou l'accueil selon le compte.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Future<Profile?>? _profile;

  @override
  void initState() {
    super.initState();
    _reload();
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(_reload);
    });
  }

  void _reload() => _profile = Repository.instance.currentProfile();

  @override
  Widget build(BuildContext context) {
    if (Supabase.instance.client.auth.currentSession == null) return const AuthScreen();
    return FutureBuilder<Profile?>(
      future: _profile,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final profile = snap.data;
        if (profile == null || !profile.isApproved) {
          return PendingScreen(onRefresh: () => setState(_reload));
        }
        return HomeScreen(profile: profile);
      },
    );
  }
}
