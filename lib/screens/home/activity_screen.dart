import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat.dart';
import '../../models/delivery.dart';
import '../../services/paged_api.dart';
import '../../services/push_service.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/paged_loader.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/ui.dart';
import '../chat/chat_screen.dart';
import 'delivery_detail_screen.dart';
import 'home_screen.dart';

/// Onglet « Activité » : livraisons (en cours puis passées) et discussions avec l'agence.
class ActivityScreen extends StatefulWidget {
  final StartDelivery onStartDelivery;

  const ActivityScreen({super.key, required this.onStartDelivery});

  @override
  State<ActivityScreen> createState() => ActivityScreenState();
}

class ActivityScreenState extends State<ActivityScreen> with WidgetsBindingObserver {
  late final PagedApi _api = context.read<PagedApi>();
  late final _deliveries = PagedLoader<Delivery>((page) => _api.myDeliveries(page: page), idOf: (d) => d.id);
  late final _chats = PagedLoader<ChatRequest>((page) => _api.chatRequests(page: page), idOf: (r) => r.id);
  StreamSubscription<int>? _deliveryPushes;
  StreamSubscription<int>? _chatPushes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Notification reçue app ouverte : statuts, messages et badges à jour.
    _deliveryPushes = PushService.deliveryUpdates.listen((_) => _deliveries.refresh());
    _chatPushes = PushService.chatUpdates.listen((_) => _chats.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deliveryPushes?.cancel();
    _chatPushes?.cancel();
    _deliveries.dispose();
    _chats.dispose();
    super.dispose();
  }

  /// Retour au premier plan : réponses ou statuts changés entre-temps.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  void _load() {
    _deliveries.refresh();
    _chats.refresh();
  }

  /// Rechargé par la navigation principale à chaque ouverture de l'onglet.
  void reload() => _load();

  Future<void> _refresh() => Future.wait([_deliveries.reset(), _chats.reset()]);

  Future<void> _openDelivery(Delivery d) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryDetailScreen(deliveryId: d.id)));
    if (mounted) _load();
  }

  Future<void> _openChat(ChatRequest r) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(requestId: r.id, initial: r)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: Text('Activité', style: Theme.of(context).textTheme.headlineMedium),
          bottom: TabBar(
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: [
              const Tab(text: 'Livraisons'),
              Tab(
                child: ListenableBuilder(
                  listenable: _chats,
                  builder: (context, _) {
                    final unread = (_chats.items ?? const <ChatRequest>[]).fold<int>(0, (sum, r) => sum + r.unread);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Messages'),
                        if (unread > 0) ...[const SizedBox(width: 6), CountBadge(count: unread)],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(onRefresh: _refresh, child: _deliveriesTab()),
            RefreshIndicator(onRefresh: _refresh, child: _chatsTab()),
          ],
        ),
      ),
    );
  }

  Widget _deliveriesTab() {
    return ListenableBuilder(
      listenable: _deliveries,
      builder: (context, _) {
        final items = _deliveries.items;
        if (items == null) {
          if (_deliveries.error != null && !_deliveries.loading) {
            return ErrorRetryView(message: _deliveries.errorMessage, onRetry: _deliveries.refresh);
          }
          return const Center(child: CircularProgressIndicator());
        }
        if (items.isEmpty && _deliveries.error == null) {
          return _Empty(
            icon: Icons.local_shipping_outlined,
            title: 'Aucune livraison',
            text: 'Vos courses apparaîtront ici, avec leur suivi en direct.',
            action: ElevatedButton(onPressed: () => widget.onStartDelivery(), child: const Text('Envoyer un colis')),
          );
        }
        final active = items.where((d) => d.isActive).toList();
        final past = items.where((d) => !d.isActive).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (_deliveries.error != null) StaleDataBanner(message: _deliveries.errorMessage, onRetry: _deliveries.refresh),
            if (active.isNotEmpty) ...[
              const SectionTitle('En cours', padding: EdgeInsets.fromLTRB(0, 12, 0, 6)),
              for (final d in active) DeliveryCard(delivery: d, onTap: () => _openDelivery(d)),
            ],
            if (past.isNotEmpty) ...[
              const SectionTitle('Passées', padding: EdgeInsets.fromLTRB(0, 20, 0, 6)),
              for (final d in past) DeliveryCard(delivery: d, onTap: () => _openDelivery(d)),
            ],
            LoadMoreFooter(loader: _deliveries),
          ],
        );
      },
    );
  }

  Widget _chatsTab() {
    return ListenableBuilder(
      listenable: _chats,
      builder: (context, _) {
        final items = _chats.items;
        if (items == null) {
          // Erreur réseau : on ne fait pas croire qu'il n'y a « aucune discussion ».
          if (_chats.error != null && !_chats.loading) {
            return ErrorRetryView(message: _chats.errorMessage, onRetry: _chats.refresh);
          }
          return const Center(child: CircularProgressIndicator());
        }
        if (items.isEmpty && _chats.error == null) {
          return const _Empty(
            icon: Icons.forum_outlined,
            title: 'Aucune discussion',
            text: "Envoyez la photo d'un colis depuis l'accueil (« Par photo ») : l'agence vous répond ici.",
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (_chats.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: StaleDataBanner(message: _chats.errorMessage, onRetry: _chats.refresh),
              ),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(indent: 76),
              _ChatTile(request: items[i], onTap: () => _openChat(items[i])),
            ],
            LoadMoreFooter(loader: _chats),
          ],
        );
      },
    );
  }
}

class _ChatTile extends StatelessWidget {
  final ChatRequest request;
  final VoidCallback onTap;

  const _ChatTile({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = request;
    final unread = r.unread > 0;
    final scheduled = r.delivery != null;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: IconSquare(
        scheduled ? Icons.local_shipping_outlined : Icons.support_agent_rounded,
        size: 44,
        background: scheduled ? AppColors.accent : AppColors.surface,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              scheduled ? 'Livraison ${r.delivery!.reference}' : 'Demande ${r.reference}',
              style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
          if (r.lastMessageAt != null)
            Text(formatTime(r.lastMessageAt!),
                style: TextStyle(fontSize: 12, color: unread ? AppColors.ink : AppColors.textHint)),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              r.lastMessage?.preview ?? r.statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: unread ? AppColors.ink : AppColors.textSecondary),
            ),
          ),
          if (unread) ...[const SizedBox(width: 8), CountBadge(count: r.unread)],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  const _Empty({required this.icon, required this.title, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    // ListView : permet le « tirer pour rafraîchir » même quand la liste est vide.
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      children: [
        Center(child: IconSquare(icon, size: 72)),
        const SizedBox(height: 20),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    );
  }
}

/// Ligne d'activité : destination, date, prix et statut, à la manière d'un historique de courses.
class DeliveryCard extends StatelessWidget {
  final Delivery delivery;
  final VoidCallback onTap;

  const DeliveryCard({super.key, required this.delivery, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final cancelled = d.status == DeliveryStatus.cancelled;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconSquare(
                  d.isInProgress ? Icons.two_wheeler_rounded : Icons.inventory_2_outlined,
                  size: 52,
                  background: d.isInProgress ? AppColors.accent : AppColors.surface,
                ),
                if (d.unreadMessages > 0) Positioned(top: -4, right: -6, child: CountBadge(count: d.unreadMessages)),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.dropoff.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: cancelled ? AppColors.textSecondary : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatDateTime(d.createdAt)} · ${formatFcfa(d.totalAmount)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    StatusChip.delivery(d),
                    if (d.isActive && !d.isPaid) StatusChip.payment(d),
                  ]),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }
}
