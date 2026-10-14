import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../utils/colors.dart';
import '../../widgets/bottom_action_bar.dart';
import '../splash_screen.dart';

/// Mot de passe oublié, sans passer par l'agence : un code est envoyé à l'email du compte,
/// le client le saisit avec son nouveau mot de passe et se retrouve connecté.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialLogin;

  const ForgotPasswordScreen({super.key, this.initialLogin = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _login = TextEditingController(text: widget.initialLogin);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// Email masqué une fois le code envoyé (étape 2), null à l'étape 1.
  String? _sentTo;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    for (final c in [_login, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _error(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.error));

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final email = await context.read<AuthService>().sendResetCode(_login.text.trim());
      if (!mounted) return;
      setState(() => _sentTo = email);
    } on ApiException catch (e) {
      if (mounted) _error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await auth.resetPassword(
        login: _login.text.trim(),
        code: _code.text.trim(),
        password: _password.text,
        confirmPassword: _confirm.text,
      );
      navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => SplashScreen.homeFor(auth)), (_) => false);
    } on ApiException catch (e) {
      if (mounted) _error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sent = _sentTo != null;
    final visibility = IconButton(
      tooltip: _obscure ? 'Afficher' : 'Masquer',
      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => setState(() => _obscure = !_obscure),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  const Icon(Icons.mark_email_read_outlined, color: AppColors.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(sent
                        ? 'Code envoyé à $_sentTo. Il est valable 15 minutes (pensez aux spams).'
                        : "Nous envoyons un code à l'email de votre compte. "
                            "Pas d'email enregistré ? Contactez l'agence."),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _login,
              enabled: !sent,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email ou téléphone', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Saisissez votre email ou téléphone' : null,
            ),
            if (sent) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Code reçu par email',
                  prefixIcon: Icon(Icons.pin_outlined),
                  counterText: '',
                ),
                validator: (v) => (v ?? '').trim().length != 6 ? 'Le code a 6 chiffres' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: visibility,
                ),
                validator: (v) => (v ?? '').length < 8 ? 'Au moins 8 caractères' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: const InputDecoration(
                  labelText: 'Confirmer le mot de passe',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) => v != _password.text ? 'Les mots de passe ne correspondent pas' : null,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _busy ? null : _sendCode, child: const Text('Renvoyer le code')),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text("Le code arrive en général en moins d'une minute.", style: textTheme.bodySmall),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        children: [
          ElevatedButton(
            onPressed: _busy ? null : (sent ? _reset : _sendCode),
            child: _busy ? const ButtonProgress() : Text(sent ? 'Changer le mot de passe' : 'Recevoir un code'),
          ),
        ],
      ),
    );
  }
}
