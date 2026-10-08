import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/ui.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (_signUp) {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'full_name': _name.text.trim()},
          // Le lien de confirmation ramène sur l'appli web plutôt que sur localhost.
          emailRedirectTo: kIsWeb ? Uri.base.removeFragment().toString() : null,
        );
        if (res.session == null && mounted) {
          setState(() => _error = 'Compte créé. Confirme ton adresse e-mail puis connecte-toi.');
        }
      } else {
        await auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
    } on AuthException catch (e) {
      setState(() => _error = _translate(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _translate(String message) {
    final m = message.toLowerCase();
    if (m.contains('invalid login')) return 'E-mail ou mot de passe incorrect.';
    if (m.contains('already registered')) return 'Un compte existe déjà avec cet e-mail.';
    if (m.contains('password should be')) return 'Le mot de passe doit faire au moins 6 caractères.';
    if (m.contains('email not confirmed')) return 'Confirme d\'abord ton adresse e-mail.';
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: Stack(children: [
          Positioned(top: -60, left: -40, child: Icon(Icons.music_note_rounded, size: 260, color: Colors.white.withValues(alpha: 0.05))),
          Positioned(bottom: -40, right: -30, child: Icon(Icons.queue_music_rounded, size: 240, color: AppColors.gold.withValues(alpha: 0.10))),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [
                  const AppLogo(size: 84),
                  const SizedBox(height: 18),
                  const Text('Appli GDC',
                      style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 40, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Le carnet de chants de la chorale',
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.white.withValues(alpha: 0.8))),
                  const SizedBox(height: 30),
                  Card(
                    elevation: 12,
                    shadowColor: Colors.black38,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(_signUp ? 'Créer mon compte' : 'Connexion', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Text(
                          _signUp
                              ? 'Ton compte sera validé par le chef de chœur.'
                              : 'Content de te revoir !',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 20),
                        if (_signUp) ...[
                          TextField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(labelText: 'Prénom et nom', prefixIcon: Icon(Icons.person_rounded)),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_rounded)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: _hidePassword,
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_hidePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                              onPressed: () => setState(() => _hidePassword = !_hidePassword),
                            ),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_signUp ? 'Créer mon compte' : 'Se connecter'),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: () => setState(() {
                            _signUp = !_signUp;
                            _error = null;
                          }),
                          child: Text(_signUp ? 'J\'ai déjà un compte' : 'Nouveau ? Créer un compte'),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
