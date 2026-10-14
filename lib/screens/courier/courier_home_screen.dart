import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/delivery.dart';
import '../../services/auth_service.dart';
import '../../services/paged_api.dart';
import '../../services/push_service.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/deadline_chip.dart';
import '../../widgets/paged_loader.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/voom_logo.dart';
import '../home/profile_screen.dart';
import 'courier_delivery_screen.dart';

/// Espace livreur : livraisons assignées par l'admin.
class CourierHomeScreen extends StatefulWidget {
  const CourierHomeScreen({super.key});

  @override
  State<CourierHomeScreen> createState() => _CourierHomeScreenState();
}

class _CourierHomeScreenState extends State<CourierHomeScreen> {
  late final PagedApi _api = context.read<PagedApi>();
  late final _todo = PagedLoader<Delivery>((page) => _api.courierDeliveries(page: page));
  late final _history = PagedLoader<Delivery>((page) => _api.courierDeliveries(history: true, page: page));

  @override
  void initState() {
    super.initState();
    _todo.refresh();
    _history.refresh();
  }

  @override
  void dispose() {
    _todo.dispose();
    _history.dispose();
    super.dispose();
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
          backgroundColor: AppColors.secondary,
          foregroundColor: AppColors.primary,
          leadingWidth: 104,
          leading: const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Center(child: VoomLogo.light(width: 92)),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mes livraisons', style: TextStyle(color: AppColors.primary)),
              Text(user?.name ?? '', style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Profil',
              icon: const Icon(Icons.account_circle),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
            ),
          ],
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.white70,
            indicatorColor: AppColors.primary,
            tabs: [Tab(text: 'À faire'), Tab(text: 'Historique')],
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

class _CourierListState extends State<_CourierList> with AutomaticKeepAliveClientMixin {
  Timer? _poll;
  StreamSubscription<int>? _pushes;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
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
      onRefresh: loader.refresh,
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: StaleDataBanner(message: loader.errorMessage, onRetry: loader.refresh),
                ),
              Padding(
                padding: const EdgeInsets.all(48),
                child: Column(children: [
                  const Icon(Icons.inbox_outlined, size: 56, color: AppColors.textHint),
                  const SizedBox(height: 12),
                  Text(
                    widget.history
                        ? 'Aucune livraison terminée.'
                        : 'Aucune livraison assignée pour le moment.\nTirez pour actualiser.',
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            ]);
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      // Livraison urgente (Express ou heure limite proche) : liseré rouge.
      shape: d.isUrgent && d.isActive
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.error, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(d.reference, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(width: 8),
                if (d.type == DeliveryType.express) const StatusChip(label: 'EXPRESS', color: AppColors.warning),
                const Spacer(),
                StatusChip.delivery(d),
              ]),
              if (d.deadlineAt != null) ...[
                const SizedBox(height: 8),
                DeadlineChip(deadline: d.deadlineAt!, done: !d.isActive),
              ],
              const SizedBox(height: 12),
              _Line(
                icon: Icons.store,
                color: AppColors.success,
                text: d.pickup.address,
                highlight: d.isActive && nextIsPickup,
              ),
              const SizedBox(height: 6),
              _Line(
                icon: Icons.flag,
                color: AppColors.error,
                text: d.dropoff.address,
                highlight: d.isActive && !nextIsPickup,
              ),
              const SizedBox(height: 10),
              Row(children: [
                Text(formatKm(d.distanceKm), style: Theme.of(context).textTheme.bodySmall),
                if (d.scheduledAt != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.schedule, size: 14),
                  const SizedBox(width: 4),
                  Text(formatDateTime(d.scheduledAt!), style: Theme.of(context).textTheme.bodySmall),
                ],
                const Spacer(),
                const Icon(Icons.chevron_right),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final bool highlight;

  const _Line({required this.icon, required this.color, required this.text, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: highlight ? FontWeight.w700 : FontWeight.normal),
        ),
      ),
    ]);
  }
}
