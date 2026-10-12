import 'package:flutter/material.dart';

import '../utils/colors.dart';

/// Mise en page des écrans de connexion / inscription : photo de marque plein cadre
/// avec slogan, puis carte ivoire qui chevauche la photo et porte le formulaire.
class AuthLayout extends StatelessWidget {
  final String photo;
  final Alignment photoAlignment;
  final String tagline;
  final double heroHeight;
  final bool showBack;
  final Widget card;
  final Widget? footer;

  const AuthLayout({
    super.key,
    required this.photo,
    required this.tagline,
    required this.card,
    this.photoAlignment = Alignment.center,
    this.heroHeight = 300,
    this.showBack = false,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: heroHeight + topInset,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
                    child: Image.asset(photo, fit: BoxFit.cover, alignment: photoAlignment),
                  ),
                  // Dégradé pour la lisibilité du slogan.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x55000000), Color(0x00000000), Color(0xCC000000)],
                        stops: [0, 0.35, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 52,
                    child: Text(
                      tagline,
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.15),
                    ),
                  ),
                  if (showBack)
                    Positioned(
                      left: 12,
                      top: topInset + 8,
                      child: IconButton.filled(
                        tooltip: 'Retour',
                        style: IconButton.styleFrom(backgroundColor: AppColors.card, foregroundColor: AppColors.secondary),
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                ],
              ),
            ),
            // La carte remonte sur la photo.
            Transform.translate(
              offset: const Offset(0, -32),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDark.withValues(alpha: 0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: card,
                ),
              ),
            ),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}
