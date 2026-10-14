import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../utils/colors.dart';
import '../../widgets/auth_layout.dart';
import '../../widgets/voom_logo.dart';
import '../splash_screen.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await auth.login(login: _loginController.text.trim(), password: _passwordController.text);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => SplashScreen.homeFor(auth)),
        (_) => false,
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AuthLayout(
      photo: 'assets/images/photo_courier.jpg',
      photoAlignment: const Alignment(0, -0.4),
      tagline: 'Livré vite,\npartout à Lomé',
      footer: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          "Déjà client de l'agence ou livreur ? Connectez-vous avec le numéro et le mot de passe "
          'reçus de VOOM, sans vous inscrire.',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall,
        ),
      ),
      card: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: VoomLogo(width: 170)),
            const SizedBox(height: 10),
            Text('Connectez-vous à votre compte', textAlign: TextAlign.center, style: textTheme.bodyMedium),
            const SizedBox(height: 20),
            TextFormField(
              controller: _loginController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Email ou téléphone',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Saisissez votre email ou téléphone' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _login(),
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Afficher' : 'Masquer',
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) => (value == null || value.isEmpty) ? 'Saisissez votre mot de passe' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ForgotPasswordScreen(initialLogin: _loginController.text.trim()),
                )),
                child: const Text('Mot de passe oublié ?'),
              ),
            ),
            const SizedBox(height: 6),
            Consumer<AuthService>(
              builder: (context, auth, _) => ElevatedButton(
                onPressed: auth.isLoading ? null : _login,
                child: auth.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary),
                      )
                    : const Text('Se connecter'),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Pas encore de compte ?', style: textTheme.bodyMedium),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                  child: const Text("S'inscrire"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
