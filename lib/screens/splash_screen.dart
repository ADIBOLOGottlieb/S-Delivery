import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../utils/colors.dart';
import '../widgets/voom_logo.dart';
import 'auth/login_screen.dart';
import 'courier/courier_home_screen.dart';
import 'home/main_screen.dart';

/// Écran d'accueil animé ; restaure la session puis redirige selon le rôle.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// Écran de départ correspondant à l'utilisateur connecté.
  static Widget homeFor(AuthService auth) {
    if (!auth.isAuthenticated) return const LoginScreen();
    return auth.user!.isCourier ? const CourierHomeScreen() : const MainScreen();
  }

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.5, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward();
    _start();
  }

  Future<void> _start() async {
    final auth = context.read<AuthService>();
    // Attend à la fois la restauration de session et une durée minimale d'animation.
    await Future.wait([auth.init(), Future.delayed(const Duration(milliseconds: 1800))]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SplashScreen.homeFor(auth)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const VoomLogo.stacked(width: 260),
                const SizedBox(height: 24),
                Text(
                  'Plis & Colis • Courses alimentaires',
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
