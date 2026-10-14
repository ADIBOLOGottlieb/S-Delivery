import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../utils/colors.dart';
import '../../widgets/bottom_action_bar.dart';

/// « Mes identifiants » : numéro, email et mot de passe (ceux reçus de l'agence peuvent être changés ici).
class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key});

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: context.read<AuthService>().user?.phoneNumber);
  late final _email = TextEditingController(text: context.read<AuthService>().user?.email);
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  final _current = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_phone, _email, _newPassword, _confirm, _current]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    final user = auth.user!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final phone = _phone.text.trim();
    final email = _email.text.trim();
    final password = _newPassword.text;
    final phoneChanged = phone != user.phoneNumber;
    final emailChanged = email != (user.email ?? '');
    if (!phoneChanged && !emailChanged && password.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Aucune modification.')));
      return;
    }

    setState(() => _saving = true);
    try {
      await auth.updateCredentials(
        currentPassword: _current.text,
        phoneNumber: phoneChanged ? phone : null,
        email: emailChanged ? email : null,
        newPassword: password.isEmpty ? null : password,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Identifiants mis à jour.'), backgroundColor: AppColors.success));
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final visibility = IconButton(
      tooltip: _obscure ? 'Afficher' : 'Masquer',
      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => setState(() => _obscure = !_obscure),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Mes identifiants')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(16)),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.secondary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Vous avez reçu vos identifiants de l'agence ? Choisissez ici un mot de passe facile à retenir.",
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Identifiant de connexion', style: textTheme.titleMedium),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Numéro de téléphone', prefixIcon: Icon(Icons.phone_outlined)),
              validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 8 ? 'Numéro invalide' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (facultatif)',
                helperText: 'Permet de récupérer votre compte en cas de mot de passe oublié',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return null;
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value) ? null : 'Email invalide';
              },
            ),
            const SizedBox(height: 22),
            Text('Nouveau mot de passe', style: textTheme.titleMedium),
            Text('Laissez vide pour garder le mot de passe actuel.', style: textTheme.bodySmall),
            const SizedBox(height: 10),
            TextFormField(
              controller: _newPassword,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: visibility,
              ),
              validator: (v) => (v ?? '').isNotEmpty && v!.length < 8 ? 'Au moins 8 caractères' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirmer le nouveau mot de passe',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (v) => v != _newPassword.text ? 'Les mots de passe ne correspondent pas' : null,
            ),
            const SizedBox(height: 22),
            Text('Confirmation', style: textTheme.titleMedium),
            const SizedBox(height: 10),
            TextFormField(
              controller: _current,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Mot de passe actuel',
                helperText: "Celui reçu de l'agence si vous ne l'avez jamais changé",
                prefixIcon: Icon(Icons.key_outlined),
              ),
              validator: (v) => (v ?? '').isEmpty ? 'Requis pour confirmer' : null,
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        children: [
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const ButtonProgress() : const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
