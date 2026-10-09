import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/ui.dart';

/// Choisir un nouveau mot de passe : après le lien « mot de passe oublié » reçu par e-mail,
/// ou depuis le menu du compte.
class NewPasswordScreen extends StatefulWidget {
  /// Appelé une fois le mot de passe changé.
  final VoidCallback onDone;

  const NewPasswordScreen({super.key, required this.onDone});

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  Future<void> _save() async {
    if (_password.text.length < 6) {
      setState(() => _error = 'Le mot de passe doit faire au moins 6 caractères.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Les deux mots de passe ne sont pas identiques.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: _password.text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mot de passe changé.')));
      widget.onDone();
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      setState(() => _error = m.contains('different from the old')
          ? 'Choisis un mot de passe différent de l\'ancien.'
          : (m.contains('session') ? 'Le lien a expiré. Redemande un e-mail depuis « Mot de passe oublié ? ».' : e.message));
    } catch (e) {
      setState(() => _error = 'Impossible de changer le mot de passe : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration field(String label) => InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_rounded),
          suffixIcon: IconButton(
            icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
            onPressed: () => setState(() => _hide = !_hide),
          ),
        );
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(children: [
                const AppLogo(size: 72),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Nouveau mot de passe', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text('Choisis un mot de passe d\'au moins 6 caractères.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 20),
                      TextField(controller: _password, obscureText: _hide, autofocus: true, decoration: field('Nouveau mot de passe')),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirm,
                        obscureText: _hide,
                        decoration: field('Confirme le mot de passe'),
                        onSubmitted: (_) => _save(),
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
                        onPressed: _busy ? null : _save,
                        child: _busy
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Enregistrer'),
                      ),
                      TextButton(onPressed: _busy ? null : widget.onDone, child: const Text('Annuler')),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
