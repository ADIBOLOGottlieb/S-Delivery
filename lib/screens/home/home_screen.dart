import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/delivery.dart';
import '../../services/auth_service.dart';
import '../../services/paged_api.dart';
import '../../utils/colors.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/paged_loader.dart';
import '../../widgets/ui.dart';
import '../../widgets/user_avatar.dart';
import '../chat/quick_request_screen.dart';
import 'delivery_detail_screen.dart';
import 'main_screen.dart';

/// Lance une nouvelle livraison (envoi, réception, programmée, adresse déjà connue).
typedef StartDelivery = Future<void> Function({DeliveryType type, bool receiving, DeliveryPoint? dropoff});

/// Accueil du client, façon apps de mobilité : « Où livrer ? », course en cours, services, adresses récentes.
class HomeScreen extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  final StartDelivery onStartDelivery;

  const HomeScreen({super.key, required this.onNavigate, required this.onStartDelivery});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  // Livraisons récentes : les anciennes restent affichées pendant le rechargement.
  late final _recent =
      PagedLoader<Delivery>((page) => context.read<PagedApi>().myDeliveries(page: page), idOf: (d) => d.id);

  @override
  void initState() {
    super.initState();
    _recent.refresh();
  }

  @override
  void dispose() {
    _recent.dispose();
    super.dispose();
  }

  void reload() => _recent.refresh();

  /// Tirer pour rafraîchir : attend vraiment la fin des chargements.
  Future<void> _refresh() async {
    final auth = context.read<AuthService>();
    await Future.wait([_recent.reset(), auth.refreshProfile()]);
  }

  /// Anti double-appui : un seul écran ouvert à la fois depuis les tuiles.
  bool _opening = false;

  Future<void> _guarded(Future<void> Function() open) async {
    if (_opening) return;
    _opening = true;
    try {
      await open();
    } finally {
      _opening = false;
    }
  }

  Future<void> _openDelivery(Delivery d) => _guarded(() async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryDetailScreen(deliveryId: d.id)));
        if (mounted) _recent.refresh();
      });

  Future<void> _photoRequest() => _guarded(() async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuickRequestScreen()));
        if (mounted) _recent.refresh();
      });

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListenableBuilder(
            listenable: _recent,
            builder: (context, _) {
              final all = _recent.items ?? const <Delivery>[];
              final active = all.where((d) => d.isActive).take(3).toList();
              final recentPlaces = _recentDropoffs(all);

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Row(
                    children: [
                      const SDeliveryLogo(height: 30),
                      const Spacer(),
                      Semantics(
                        button: true,
                        label: 'Mon compte',
                        child: GestureDetector(
                          onTap: () => widget.onNavigate(MainScreen.tabProfile),
                          child: UserAvatar(user: user, radius: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text('Bonjour ${user?.firstName ?? ''}', style: textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text('Où livrons-nous ?', style: textTheme.headlineLarge),
                  const SizedBox(height: 18),
                  _WhereToBar(
                    onTap: () => widget.onStartDelivery(),
                    onSchedule: () => widget.onStartDelivery(type: DeliveryType.programmee),
                  ),
                  if (_recent.items == null && _recent.error != null && !_recent.loading)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: StaleDataBanner(message: _recent.errorMessage, onRetry: _recent.refresh),
                    ),
                  for (final d in active)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: ActiveDeliveryCard(delivery: d, onTap: () => _openDelivery(d)),
                    ),
                  const SectionTitle('Services'),
                  _ServicesGrid(
                    onSend: () => widget.onStartDelivery(),
                    onReceive: () => widget.onStartDelivery(receiving: true),
                    onSchedule: () => widget.onStartDelivery(type: DeliveryType.programmee),
                    onPhoto: _photoRequest,
                  ),
                  if (recentPlaces.isNotEmpty) ...[
                    SectionTitle(
                      'Récents',
                      trailing: TextButton(
                        onPressed: () => widget.onNavigate(MainScreen.tabDeliveries),
                        child: const Text('Activité'),
                      ),
                    ),
                    for (final p in recentPlaces)
                      ListRow(
                        icon: Icons.history_rounded,
                        title: p.address,
                        subtitle: p.contactName == null ? null : 'Pour ${p.contactName}',
                        onTap: () => widget.onStartDelivery(dropoff: p),
                      ),
                  ],
                  const SectionTitle('Pourquoi S-Delivery'),
                  const _Highlights(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Trois dernières adresses de livraison différentes, pour recommander en un appui.
  static List<DeliveryPoint> _recentDropoffs(List<Delivery> deliveries) {
    final seen = <String>{};
    final places = <DeliveryPoint>[];
    for (final d in deliveries) {
      final key = d.dropoff.address.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      places.add(d.dropoff);
      if (places.length == 3) break;
    }
    return places;
  }
}

/// Barre « Où livrer ? » avec la puce « Maintenant » (programmer plus tard).
class _WhereToBar extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onSchedule;

  const _WhereToBar({required this.onTap, required this.onSchedule});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 26),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Où livrer ?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
              ),
              Material(
                color: Colors.white,
                shape: const StadiumBorder(),
                child: InkWell(
                  onTap: onSchedule,
                  customBorder: const StadiumBorder(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Programmer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Course en cours : bloc noir avec étape, progression lime et destination.
class ActiveDeliveryCard extends StatelessWidget {
  final Delivery delivery;
  final VoidCallback onTap;

  const ActiveDeliveryCard({super.key, required this.delivery, required this.onTap});

  static String headline(Delivery d) => switch (d.status) {
        DeliveryStatus.assigned => 'Votre livreur arrive',
        DeliveryStatus.pickedUp => 'Colis en route',
        DeliveryStatus.delivered => 'Colis livré',
        DeliveryStatus.cancelled => 'Livraison annulée',
        _ => switch (d.paymentStatus) {
            PaymentStatus.verified => 'Recherche d\'un livreur',
            PaymentStatus.submitted => 'Paiement en vérification',
            _ => 'Paiement en attente',
          },
      };

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    return Material(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    d.isInProgress ? 'EN DIRECT · ${d.reference}' : d.reference,
                    style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                  ),
                  const Spacer(),
                  if (d.unreadMessages > 0) CountBadge(count: d.unreadMessages),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                headline(d),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6),
              ),
              const SizedBox(height: 14),
              ProgressSteps(step: d.progressStep, color: AppColors.accent, track: Colors.white24),
              const SizedBox(height: 14),
              Row(
                children: [
                  const StopDot(pickup: false, color: Colors.white, size: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      d.dropoff.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
              if (d.courier != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${d.courier!.name}${d.courier!.vehicle == null ? '' : ' · ${d.courier!.vehicle}'}',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ] else if (d.canPay) ...[
                const SizedBox(height: 6),
                const Text('Touchez pour payer et confirmer la course', style: TextStyle(color: AppColors.accent, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ServicesGrid extends StatelessWidget {
  final VoidCallback onSend;
  final VoidCallback onReceive;
  final VoidCallback onSchedule;
  final VoidCallback onPhoto;

  const _ServicesGrid({required this.onSend, required this.onReceive, required this.onSchedule, required this.onPhoto});

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap, {bool highlight = false}) => Expanded(
          child: Semantics(
            button: true,
            label: title,
            excludeSemantics: true,
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconSquare(
                            icon,
                            size: 40,
                            background: highlight ? AppColors.accent : Colors.white,
                          ),
                          const Spacer(),
                          const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.textHint),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(subtitle, maxLines: 2, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    return Column(
      children: [
        Row(children: [
          tile(Icons.north_east_rounded, 'Envoyer', 'Un pli, un colis, du point A au point B', onSend, highlight: true),
          const SizedBox(width: 12),
          tile(Icons.south_west_rounded, 'Recevoir', 'On récupère pour vous et on vous livre', onReceive),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          tile(Icons.event_rounded, 'Programmer', 'Choisissez le jour et l\'heure de passage', onSchedule),
          const SizedBox(width: 12),
          tile(Icons.photo_camera_outlined, 'Par photo', 'Une photo suffit, on fait le reste', onPhoto),
        ]),
      ],
    );
  }
}

/// Atouts du service, en cartes horizontales.
class _Highlights extends StatelessWidget {
  const _Highlights();

  @override
  Widget build(BuildContext context) {
    Widget card(IconData icon, String title, String text, {bool dark = false}) => Container(
          width: 230,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: dark ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: dark ? AppColors.accent : AppColors.ink),
              const SizedBox(height: 12),
              Text(title,
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: dark ? Colors.white : AppColors.ink)),
              const SizedBox(height: 4),
              Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: dark ? Colors.white70 : AppColors.textSecondary)),
            ],
          ),
        );

    return SizedBox(
      height: 150,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          card(Icons.bolt_rounded, 'Paiement intégré', 'Flooz, Mixx by Yas ou carte, directement dans l\'app.', dark: true),
          const SizedBox(width: 12),
          card(Icons.pin_outlined, 'Code de remise', 'Le colis n\'est remis qu\'avec votre code à 4 chiffres.'),
          const SizedBox(width: 12),
          card(Icons.near_me_outlined, 'Suivi en direct', 'Suivez votre livreur sur la carte et écrivez-lui.'),
        ],
      ),
    );
  }
}
