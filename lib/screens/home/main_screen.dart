import 'package:flutter/material.dart';

import '../../models/delivery.dart';
import '../../services/push_service.dart';
import '../../widgets/photos.dart';
import '../chat/quick_request_screen.dart';
import 'activity_screen.dart';
import 'delivery_detail_screen.dart';
import 'home_screen.dart';
import 'new_delivery_screen.dart';
import 'profile_screen.dart';

/// Navigation principale du client : Accueil, Activité, Compte (barre blanche, icône active en noir).
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static const tabHome = 0;
  static const tabDeliveries = 1;
  static const tabProfile = 2;

  /// Démarre une commande puis ouvre son suivi une fois créée.
  static Future<void> startDelivery(
    BuildContext context, {
    DeliveryType type = DeliveryType.colis,
    bool receiving = false,
    DeliveryPoint? dropoff,
  }) async {
    final navigator = Navigator.of(context);
    final created = await navigator.push<Delivery>(
      MaterialPageRoute(
        builder: (_) => NewDeliveryScreen(initialType: type, receiving: receiving, initialDropoff: dropoff),
      ),
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
  final _activityKey = GlobalKey<ActivityScreenState>();

  /// Anti double-appui : un seul formulaire ouvert.
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumePhotos();
      // Notification touchée avant la connexion : ouverte une fois l'accueil affiché.
      PushService.openPending();
    });
  }

  /// Android a fermé l'app pendant une prise de vue : on rouvre l'envoi par photo avec les photos déjà prises.
  Future<void> _resumePhotos() async {
    final photos = await PhotoDraft.recover();
    if (photos.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 8),
      content: Text(
        "Le téléphone a fermé l'application pendant la photo : vos photos ont été gardées. "
        "Envoyez-les à l'agence ou recommencez le formulaire.",
      ),
    ));
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => QuickRequestScreen(initialPhotos: photos)),
    );
    if (!mounted) return;
    _activityKey.currentState?.reload();
  }

  void _goTo(int index) {
    setState(() => _currentIndex = index);
    if (index == MainScreen.tabDeliveries) _activityKey.currentState?.reload();
    if (index == MainScreen.tabHome) _homeKey.currentState?.reload();
  }

  Future<void> _startDelivery({DeliveryType type = DeliveryType.colis, bool receiving = false, DeliveryPoint? dropoff}) async {
    if (_starting) return;
    _starting = true;
    try {
      await MainScreen.startDelivery(context, type: type, receiving: receiving, dropoff: dropoff);
    } finally {
      _starting = false;
    }
    if (!mounted) return;
    _homeKey.currentState?.reload();
    _activityKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(key: _homeKey, onNavigate: _goTo, onStartDelivery: _startDelivery),
      ActivityScreen(key: _activityKey, onStartDelivery: _startDelivery),
      const ProfileScreen(),
    ];

    // Retour Android sur un autre onglet : revient d'abord à l'Accueil au lieu de quitter l'app.
    return PopScope(
      canPop: _currentIndex == MainScreen.tabHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(MainScreen.tabHome);
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: screens),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFEAEAEA))),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _goTo,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Accueil'),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Activité',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Compte',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
