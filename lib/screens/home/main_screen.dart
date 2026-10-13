import 'package:flutter/material.dart';

import '../../models/delivery.dart';
import '../../utils/colors.dart';
import 'delivery_detail_screen.dart';
import 'home_screen.dart';
import 'new_delivery_screen.dart';
import 'plis_colis_screen.dart';
import 'product_catalog_screen.dart';
import 'profile_screen.dart';

/// Navigation principale du client : barre flottante avec bouton central « Livrer ».
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static const tabHome = 0;
  static const tabAgro = 1;
  static const tabDeliveries = 2;
  static const tabProfile = 3;

  /// Démarre une commande : formulaire Plis & Colis, qui propose aussi
  /// la « programmation par photo » sous les types de livraison.
  static Future<void> startDelivery(BuildContext context, {DeliveryType type = DeliveryType.colis}) async {
    final navigator = Navigator.of(context);
    final created = await navigator.push<Delivery>(
      MaterialPageRoute(builder: (_) => NewDeliveryScreen(initialType: type)),
    );
    if (created != null) {
      await navigator.push(MaterialPageRoute(builder: (_) => DeliveryDetailScreen(deliveryId: created.id)));
    }
  }

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = MainScreen.tabHome;
  final _homeKey = GlobalKey<HomeScreenState>();
  final _trackingKey = GlobalKey<PlisColisScreenState>();

  void _goTo(int index) {
    setState(() => _currentIndex = index);
    if (index == MainScreen.tabDeliveries) _trackingKey.currentState?.reload();
  }

  Future<void> _startDelivery() async {
    await MainScreen.startDelivery(context);
    if (!mounted) return;
    _homeKey.currentState?.reload();
    _trackingKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(key: _homeKey, onNavigate: _goTo, onStartDelivery: _startDelivery),
      const ProductCatalogScreen(category: ProductCategory.agro),
      PlisColisScreen(key: _trackingKey),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: _FloatingNavBar(
        currentIndex: _currentIndex,
        onTap: _goTo,
        onAction: _startDelivery,
      ),
    );
  }
}

/// Barre de navigation flottante (pilule noire) avec action centrale jaune.
class _FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onAction;

  const _FloatingNavBar({required this.currentIndex, required this.onTap, required this.onAction});

  @override
  Widget build(BuildContext context) {
    Widget item(int index, IconData icon, IconData activeIcon, String label) => Expanded(
          child: _NavItem(
            icon: currentIndex == index ? activeIcon : icon,
            label: label,
            selected: currentIndex == index,
            onTap: () => onTap(index),
          ),
        );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(34),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              item(MainScreen.tabHome, Icons.home_outlined, Icons.home_rounded, 'Accueil'),
              item(MainScreen.tabAgro, Icons.shopping_basket_outlined, Icons.shopping_basket, 'Courses'),
              _CenterAction(onTap: onAction),
              item(MainScreen.tabDeliveries, Icons.receipt_long_outlined, Icons.receipt_long, 'Suivi'),
              item(MainScreen.tabProfile, Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 8, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 22, color: selected ? AppColors.onPrimary : Colors.white60),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton central « Livrer » : action principale de l'app.
class _CenterAction extends StatelessWidget {
  final VoidCallback onTap;

  const _CenterAction({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        label: 'Nouvelle livraison',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.45), blurRadius: 12)],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delivery_dining, color: AppColors.onPrimary, size: 26),
                Text('Livrer', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.onPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
