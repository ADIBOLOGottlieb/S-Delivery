import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/push_service.dart';
import '../utils/colors.dart';
import '../widgets/brand_logo.dart';
import 'auth/login_screen.dart';
import 'courier/courier_home_screen.dart';
import 'home/main_screen.dart';

/// Écran de démarrage (noir, logo animé) ; restaure la session puis redirige selon le rôle.
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
  late final AnimationController _controller =
      AnimationController(duration: const Duration(milliseconds: 1100), vsync: this)..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<double> _scale =
      Tween<double>(begin: 0.85, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final auth = context.read<AuthService>();
    // Attend à la fois la restauration de session et une durée minimale d'animation.
    await Future.wait([auth.init(), Future.delayed(const Duration(milliseconds: 1500))]);
    // Session expirée pendant le démarrage : SessionGuard a déjà affiché la connexion.
    if (!mounted) return PushService.markAppReady();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => SplashScreen.homeFor(auth),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
    // Notification touchée pour lancer l'app : ouverte par-dessus l'accueil.
    PushService.markAppReady();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SDeliveryMark(size: 96, background: null),
                SizedBox(height: 20),
                SDeliveryLogo(height: 40, light: true, showMark: false),
                SizedBox(height: 10),
                Text('Livré vite, partout à Lomé', style: TextStyle(color: Colors.white60, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
