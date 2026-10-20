import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/delivery.dart';
import '../../services/auth_service.dart';
import '../../services/courier_location_service.dart';
import '../../services/delivery_service.dart';
import '../../services/paged_api.dart';
import '../../services/push_service.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/deadline_chip.dart';
import '../../widgets/paged_loader.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/ui.dart';
import '../../widgets/user_avatar.dart';
import '../home/profile_screen.dart';
import 'courier_delivery_screen.dart';

/// Espace livreur : courses assignées par l'agence, position partagée pendant les courses.
class CourierHomeScreen extends StatefulWidget {
  const CourierHomeScreen({super.key});

  @override
  State<CourierHomeScreen> createState() => _CourierHomeScreenState();
}

class _CourierHomeScreenState extends State<CourierHomeScreen> {
  late final PagedApi _api = context.read<PagedApi>();
  late final _todo = PagedLoader<Delivery>((page) => _api.courierDeliveries(page: page), idOf: (d) => d.id);
  late final _history = PagedLoader<Delivery>(
    (page) => _api.courierDeliveries(history: true, page: page),
    idOf: (d) => d.id,
  );
  late final _location = CourierLocationService(context.read<DeliveryService>());

  @override
  void initState() {
    super.initState();
    // Notification touchée avant la connexion : ouverte une fois l'espace livreur affiché.
    WidgetsBinding.instance.addPostFrameCallback((_) => PushService.openPending());
    _todo.addListener(_syncLocation);
    _todo.refresh();
    _history.refresh();
  }

  @override
  void dispose() {
    _todo.removeListener(_syncLocation);
    _location.stop();
    _todo.dispose();
    _history.dispose();
    super.dispose();
  }

  /// Position partagée tant qu'une course est en cours (le client suit le livreur sur la carte).
  void _syncLocation() {
    final active = (_todo.items ?? const <Delivery>[]).any((d) => d.isInProgress);
    if (active) {
      _location.start();
    } else {
      _location.stop();
    }
  }

  /// Retour d'une course : son statut a pu changer, elle peut passer d'un onglet à l'autre.
  void _reloadAll() {
    _todo.refresh();
    _history.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: const SDeliveryLogo(height: 30),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
                child: UserAvatar(user: user, radius: 18),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text('Mes courses', style: Theme.of(context).textTheme.headlineMedium),
                ),
                const TabBar(
                  tabAlignment: TabAlignment.start,
                  isScrollable: true,
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  tabs: [Tab(text: 'À faire'), Tab(text: 'Historique')],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(children: [
          _CourierList(loader: _todo, history: false, onReturn: _reloadAll),
          _CourierList(loader: _history, history: true, onReturn: _reloadAll),
        ]),
      ),
    );
  }
}

class _CourierList extends StatefulWidget {
  final PagedLoader<Delivery> loader;
  final bool history;
  final VoidCallback onReturn;

  const _CourierList({required this.loader, required this.history, required this.onReturn});

  @override
  State<_CourierList> createState() => _CourierListState();
}

class _CourierListState extends State<_CourierList> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  Timer? _poll;
  StreamSubscription<int>? _pushes;

  @override
  bool get wantKeepAlive => true;

  /// Retour au premier plan : « À faire » est relu tout de suite (sans attendre le prochain cycle).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.history) widget.loader.refresh();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.history) {
      // Nouvelles courses assignées par l'agence : « À faire » se met à jour toute seule.
      _poll = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_visible) widget.loader.refresh();
      });
      _pushes = PushService.deliveryUpdates.listen((_) => widget.loader.refresh());
    }
  }

  /// Onglet affiché, écran au premier plan et application ouverte.
  bool get _visible {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    final tabs = DefaultTabController.maybeOf(context);
    return (route?.isCurrent ?? true) &&
        (tabs == null || tabs.index == 0) &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pushes?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _open(Delivery d) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CourierDeliveryScreen(deliveryId: d.id)));
    if (mounted) widget.onReturn();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final loader = widget.loader;
    return RefreshIndicator(
      onRefresh: loader.reset,
      child: ListenableBuilder(
        listenable: loader,
        builder: (context, _) {
          final items = loader.items;
          if (items == null) {
            if (loader.error != null && !loader.loading) {
              return ErrorRetryView(message: loader.errorMessage, onRetry: loader.refresh);
            }
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return ListView(children: [
              if (loader.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: StaleDataBanner(message: loader.errorMessage, onRetry: loader.refresh),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
                child: Column(children: [
                  const IconSquare(Icons.inbox_outlined, size: 72),
                  const SizedBox(height: 16),
                  Text(
                    widget.history ? 'Aucune course terminée.' : 'Aucune course pour le moment.\nTirez pour actualiser.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ]),
              ),
            ]);
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.paddingOf(context).bottom),
            children: [
              if (loader.error != null) StaleDataBanner(message: loader.errorMessage, onRetry: loader.refresh),
              for (final d in items) _CourierCard(delivery: d, onTap: () => _open(d)),
              LoadMoreFooter(loader: loader),
            ],
          );
        },
      ),
    );
  }
}

class _CourierCard extends StatelessWidget {
  final Delivery delivery;
  final VoidCallback onTap;

  const _CourierCard({required this.delivery, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    // Prochaine étape : récupérer en A tant que le colis n'est pas pris, sinon livrer en B.
    final nextIsPickup = d.status == DeliveryStatus.assigned;
    final urgent = d.isUrgent && d.isActive;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          // Livraison urgente (Express ou heure limite proche) : liseré rouge.
          side: BorderSide(color: urgent ? AppColors.error : AppColors.border, width: urgent ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (d.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        nextIsPickup ? 'À RÉCUPÉRER' : 'À LIVRER',
                        style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      ),
                    )
                  else
                    StatusChip.delivery(d),
                  const SizedBox(width: 8),
                  if (d.type == DeliveryType.express) const StatusChip(label: 'Express', color: AppColors.error),
                  const Spacer(),
                  if (d.unreadMessages > 0) ...[CountBadge(count: d.unreadMessages), const SizedBox(width: 8)],
                  Text(d.reference, style: Theme.of(context).textTheme.labelSmall),
                ]),
                if (d.deadlineAt != null) ...[
                  const SizedBox(height: 10),
                  DeadlineChip(deadline: d.deadlineAt!, done: !d.isActive),
                ],
                const SizedBox(height: 14),
                RouteStops(
                  pickup: d.pickup.address,
                  dropoff: d.dropoff.address,
                  pickupLabel: 'Récupération',
                  dropoffLabel: 'Livraison',
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Text(formatKm(d.distanceKm), style: Theme.of(context).textTheme.bodySmall),
                  if (d.scheduledAt != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(formatDateTime(d.scheduledAt!), style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (d.parcelAmount != null) ...[
                    const SizedBox(width: 12),
                    Text('À encaisser ${formatFcfa(d.parcelAmount!)}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.warning)),
                  ],
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
