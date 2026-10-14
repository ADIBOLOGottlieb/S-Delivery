import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/delivery.dart';
import '../../models/product.dart';
import '../../services/auth_service.dart';
import '../../services/delivery_service.dart';
import '../../services/paged_api.dart';
import '../../utils/colors.dart';
import '../../widgets/paged_loader.dart';
import '../../widgets/promo_carousel.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/user_avatar.dart';
import 'delivery_detail_screen.dart';
import 'main_screen.dart';
import 'new_delivery_screen.dart';
import 'plis_colis_screen.dart';
import 'product_catalog_screen.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  final VoidCallback onStartDelivery;

  const HomeScreen({super.key, required this.onNavigate, required this.onStartDelivery});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  // Livraisons récentes : les anciennes restent affichées pendant le rechargement.
  late final _recent = PagedLoader<Delivery>((page) => context.read<PagedApi>().myDeliveries(page: page));
  late Future<List<Promotion>> _promos;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _recent.dispose();
    super.dispose();
  }

  void _load() {
    _recent.refresh();
    _promos = context.read<DeliveryService>().promotions().catchError((_) => <Promotion>[]);
  }

  void reload() => setState(_load);

  Future<void> _refresh() async {
    final auth = context.read<AuthService>();
    setState(_load);
    await Future.wait([_recent.refresh(), auth.refreshProfile()]);
  }

  Future<void> _newDelivery(DeliveryType type) async {
    final created = await Navigator.of(context).push<Delivery>(
      MaterialPageRoute(builder: (_) => NewDeliveryScreen(initialType: type)),
    );
    if (created != null && mounted) {
      setState(_load);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryDetailScreen(deliveryId: created.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // Fond crème chaud plutôt que blanc pur.
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              // En-tête jaune : salutation, photo de profil et les 3 services en ronds photo.
              Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFFFFD866)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Bonjour ${user?.firstName ?? ''},', style: textTheme.bodyLarge),
                              Text(
                                'Que livrons-nous ?',
                                style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        Semantics(
                          button: true,
                          label: 'Mon profil',
                          child: GestureDetector(
                            onTap: () => widget.onNavigate(MainScreen.tabProfile),
                            child: Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: UserAvatar(user: user, radius: 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Les 3 services, en ronds photo centrés.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PhotoCircle(
                          asset: 'assets/images/photo_bags.jpg',
                          label: 'Plis & Colis',
                          onTap: () => _newDelivery(DeliveryType.colis),
                        ),
                        _PhotoCircle(
                          asset: 'assets/images/photo_courier_bags.jpg',
                          alignment: const Alignment(0, -0.75),
                          label: 'Programmée',
                          onTap: () => _newDelivery(DeliveryType.programmee),
                        ),
                        _PhotoCircle(
                          asset: 'assets/images/photo_food.jpg',
                          label: 'Courses alimentaires',
                          onTap: () => widget.onNavigate(MainScreen.tabAgro),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Annonces promo gérées par l'admin (bandeau défilant).
              FutureBuilder<List<Promotion>>(
                future: _promos,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(padding: EdgeInsets.only(top: 20), child: Skeleton(height: 150, radius: 20));
                  }
                  final promos = snapshot.data ?? const <Promotion>[];
                  if (promos.isEmpty) return const _BrandBanner();
                  return Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: PromoCarousel(
                      promotions: promos,
                      onTap: (promo) {
                        if (promo.product != null) showProductSheet(context, promo.product!);
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              _QuickOrderCard(onTap: widget.onStartDelivery),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Livraisons récentes', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  TextButton(
                    onPressed: () => widget.onNavigate(MainScreen.tabDeliveries),
                    child: const Text('Voir tout'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: _recent,
                builder: (context, _) {
                  final all = _recent.items;
                  if (all == null) {
                    // Erreur réseau : message + « Réessayer » (et non « Aucune livraison »).
                    if (_recent.error != null && !_recent.loading) {
                      return StaleDataBanner(message: _recent.errorMessage, onRetry: _recent.refresh);
                    }
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final items = all.take(3).toList();
                  if (items.isEmpty && _recent.error != null) {
                    return StaleDataBanner(message: _recent.errorMessage, onRetry: _recent.refresh);
                  }
                  if (items.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const Icon(Icons.inbox_outlined, size: 40, color: AppColors.textHint),
                            const SizedBox(height: 8),
                            Text('Aucune livraison pour le moment', style: textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final d in items)
                        DeliveryCard(
                          delivery: d,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => DeliveryDetailScreen(deliveryId: d.id)),
                            );
                            if (mounted) _recent.refresh();
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Raccourci de commande (formulaire, avec l'option « programmation par photo »).
class _QuickOrderCard extends StatelessWidget {
  final VoidCallback onTap;

  const _QuickOrderCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.secondary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.delivery_dining, color: AppColors.onPrimary, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Demander une livraison',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Formulaire ou programmation par photo',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bannière de marque affichée quand aucune promo n'est publiée.
class _BrandBanner extends StatelessWidget {
  const _BrandBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 150,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/images/photo_courier.jpg', fit: BoxFit.cover, alignment: const Alignment(0, -0.5)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xE6000000), Color(0x00000000)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Livré vite,\npartout à Lomé',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    SizedBox(height: 6),
                    Text('Colis, courses et produits frais', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Service de l'accueil : photo réaliste dans un rond à liseré blanc, libellé dessous.
class _PhotoCircle extends StatelessWidget {
  final String asset;
  final String label;
  final VoidCallback onTap;
  final Alignment alignment;

  const _PhotoCircle({
    required this.asset,
    required this.label,
    required this.onTap,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 96,
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: ClipOval(child: Image.asset(asset, fit: BoxFit.cover, alignment: alignment)),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
