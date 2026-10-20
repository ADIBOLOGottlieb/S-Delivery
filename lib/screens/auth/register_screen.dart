import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/support_phone.dart';
import '../../utils/colors.dart';
import '../../utils/launchers.dart';
import '../../widgets/auth_layout.dart';
import '../home/main_screen.dart';

/// Inscription des clients. Les comptes livreurs sont créés par l'admin.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController(text: '+228 ');
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _openPrivacy() async {
    final url = await SupportPhone.privacyUrl(context.read<ApiClient>());
    if (mounted) await openWebPage(context, url);
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await auth.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phoneNumber: _phoneController.text.replaceAll(' ', ''),
        password: _passwordController.text,
        confirmPassword: _confirmPasswordController.text,
      );
      navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainScreen()), (_) => false);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Créez votre compte\nen 1 minute.',
      subtitle: 'Demandez vos livraisons en quelques secondes.',
      showBack: true,
      card: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Créer un compte client', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nom complet', prefixIcon: Icon(Icons.person_outlined)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Saisissez votre nom' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Numéro de téléphone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    return digits.length < 8 ? 'Saisissez un numéro valide' : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (facultatif)',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : 'Email invalide';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Saisissez un mot de passe';
                    if (v.length < 8) return 'Au moins 8 caractères';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscurePassword,
                  decoration: const InputDecoration(
                    labelText: 'Confirmer le mot de passe',
                    prefixIcon: Icon(Icons.lock_outlined),
                  ),
                  validator: (v) => v != _passwordController.text ? 'Les mots de passe ne correspondent pas' : null,
                ),
                const SizedBox(height: 32),
                Consumer<AuthService>(
                  builder: (context, auth, _) => ElevatedButton(
                    onPressed: auth.isLoading ? null : _register,
                    child: auth.isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary),
                          )
                        : const Text("S'inscrire"),
                  ),
                ),
                const SizedBox(height: 10),
                // Consentement : lien vers la politique de confidentialité (ouverte dans le navigateur).
                TextButton(
                  onPressed: _openPrivacy,
                  child: const Text(
                    'En créant un compte, vous acceptez la politique de confidentialité',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, decoration: TextDecoration.underline),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Déjà un compte ? ', style: Theme.of(context).textTheme.bodyMedium),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Se connecter'),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }
}
