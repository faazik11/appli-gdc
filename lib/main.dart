import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/new_password_screen.dart';
import 'screens/pending_screen.dart';
import 'services/offline.dart';
import 'services/repository.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  // Sans connexion, la session enregistrée est gardée et l'appli s'ouvre sur les données enregistrées.
  // Flux « implicite » : les liens reçus par e-mail (confirmation, mot de passe oublié) marchent
  // même ouverts dans un autre navigateur que celui de la demande (ex. Safari au lieu de l'icône GDC).
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit),
  );
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
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
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

  /// Arrivée par le lien « mot de passe oublié » : on demande le nouveau mot de passe.
  bool _recovering = false;

  @override
  void initState() {
    super.initState();
    _reload();
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) Offline.clearLastProfile();
      if (state.event == AuthChangeEvent.passwordRecovery) _recovering = true;
      if (mounted) setState(_reload);
    }, onError: (_) {});
  }

  void _reload() => _profile = Repository.instance.currentProfile();

  @override
  Widget build(BuildContext context) {
    if (_recovering && Supabase.instance.client.auth.currentSession != null) {
      return NewPasswordScreen(onDone: () => setState(() => _recovering = false));
    }
    if (Supabase.instance.client.auth.currentSession == null) {
      // Pas de session active : soit déconnecté, soit hors connexion (la session n'a pas pu être rafraîchie).
      return FutureBuilder<Map<String, dynamic>?>(
        future: Offline.lastProfile(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final row = snap.data;
          if (row == null) return const AuthScreen();
          final profile = Profile.fromMap(row);
          if (!profile.isApproved) return const AuthScreen();
          Offline.userId = profile.id;
          return HomeScreen(profile: profile);
        },
      );
    }
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
