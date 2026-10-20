import 'package:flutter/material.dart';

import '../utils/colors.dart';
import 'brand_logo.dart';

/// Mise en page des écrans de connexion / inscription : en-tête noir avec le logo et un titre fort,
/// puis feuille blanche arrondie qui porte le formulaire (style des apps de mobilité).
class AuthLayout extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final Widget card;
  final Widget? footer;

  const AuthLayout({
    super.key,
    required this.title,
    this.subtitle,
    required this.card,
    this.showBack = false,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child:
            Padding(
              padding: EdgeInsets.fromLTRB(24, top + 16, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (showBack) ...[
                        IconButton(
                          tooltip: 'Retour',
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: IconButton.styleFrom(foregroundColor: Colors.white),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 4),
                      ],
                      const SDeliveryLogo(height: 34, light: true),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      height: 1.1,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 10),
                    Text(subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 15.5, height: 1.35)),
                  ],
                ],
              ),
            ),
          ),
          // La feuille blanche occupe tout l'espace restant, jusqu'en bas de l'écran.
          SliverFillRemaining(
            hasScrollBody: false,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + MediaQuery.paddingOf(context).bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [card, if (footer != null) ...[const SizedBox(height: 16), footer!]],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
