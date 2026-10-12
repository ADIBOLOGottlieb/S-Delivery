import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat.dart';
import '../../models/delivery.dart';
import '../../services/auth_service.dart';
import '../../services/delivery_service.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/status_chip.dart';
import '../chat/chat_screen.dart';
import 'delivery_detail_screen.dart';

/// Onglet « Suivi » : livraisons du client et discussions avec l'agence.
class PlisColisScreen extends StatefulWidget {
  const PlisColisScreen({super.key});

  @override
  State<PlisColisScreen> createState() => PlisColisScreenState();
}

class PlisColisScreenState extends State<PlisColisScreen> {
  late Future<List<Delivery>> _deliveries;
  late Future<List<ChatRequest>> _chats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final service = context.read<DeliveryService>();
    _deliveries = service.myDeliveries();
    _chats = service.chatRequests().catchError((_) => <ChatRequest>[]);
  }

  /// Rechargé par la navigation principale à chaque ouverture de l'onglet.
  void reload() => setState(_load);

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_deliveries.catchError((_) => <Delivery>[]), _chats]);
  }

  Future<void> _openDelivery(Delivery d) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryDetailScreen(deliveryId: d.id)));
    if (mounted) setState(_load);
  }

  Future<void> _openChat(ChatRequest r) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(requestId: r.id, initial: r)));
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Suivi'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                height: 44,
                // Pilule noire sur le fond crème, onglet actif en jaune.
                decoration: BoxDecoration(color: AppColors.secondary, borderRadius: BorderRadius.circular(22)),
                padding: const EdgeInsets.all(3),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(22)),
                  labelColor: AppColors.onPrimary,
                  unselectedLabelColor: Colors.white70,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  tabs: [
                    const Tab(text: 'Livraisons'),
                    Tab(
                      child: FutureBuilder<List<ChatRequest>>(
                        future: _chats,
                        builder: (context, snap) {
                          final unread = (snap.data ?? const <ChatRequest>[]).fold<int>(0, (sum, r) => sum + r.unread);
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Discussions'),
                              if (unread > 0) ...[const SizedBox(width: 6), _Badge(count: unread)],
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
    return FutureBuilder<List<Delivery>>(
      future: _deliveries,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorRetry(message: snapshot.error.toString(), onRetry: () => setState(_load));
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const _Empty(
            icon: Icons.local_shipping_outlined,
            text: 'Aucune livraison pour le moment.\nAppuyez sur « Livrer » pour commencer.',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [for (final d in items) DeliveryCard(delivery: d, onTap: () => _openDelivery(d))],
        );
      },
    );
  }

  Widget _chatsTab() {
    final regular = context.watch<AuthService>().user?.isRegular ?? false;
    return FutureBuilder<List<ChatRequest>>(
      future: _chats,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data ?? const <ChatRequest>[];
        if (items.isEmpty) {
          return _Empty(
            icon: Icons.forum_outlined,
            text: regular
                ? 'Aucune discussion.\nAppuyez sur « Livrer » et envoyez les photos de vos articles.'
                : 'Après votre première livraison, commandez en envoyant simplement des photos : '
                    "l'agence programme tout avec vous ici.",
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
          itemBuilder: (context, i) => _ChatTile(request: items[i], onTap: () => _openChat(items[i])),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: scheduled ? AppColors.success : AppColors.primary,
        child: Icon(scheduled ? Icons.local_shipping : Icons.support_agent,
            color: scheduled ? Colors.white : AppColors.onPrimary),
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
                style: TextStyle(fontSize: 12, color: unread ? AppColors.primaryDark : AppColors.textHint)),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              r.lastMessage?.preview ?? r.statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: unread ? AppColors.textPrimary : AppColors.textSecondary),
            ),
          ),
          if (unread) ...[const SizedBox(width: 8), _Badge(count: r.unread)],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(10)),
      child: Text('$count',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    // ListView : permet le « tirer pour rafraîchir » même quand la liste est vide.
    return ListView(
      padding: const EdgeInsets.all(40),
      children: [
        const SizedBox(height: 40),
        Icon(icon, size: 64, color: AppColors.textHint),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// Carte résumant une livraison (utilisée par le client).
class DeliveryCard extends StatelessWidget {
  final Delivery delivery;
  final VoidCallback onTap;

  const DeliveryCard({super.key, required this.delivery, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(d.reference, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('· ${d.type.label}', style: Theme.of(context).textTheme.bodySmall),
                  if (d.photos.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.photo_library_outlined, size: 16, color: AppColors.textSecondary),
                  ],
                  const Spacer(),
                  StatusChip.delivery(d),
                ],
              ),
              const SizedBox(height: 10),
              _PointLine(label: 'A', color: AppColors.success, text: d.pickup.address),
              const SizedBox(height: 4),
              _PointLine(label: 'B', color: AppColors.error, text: d.dropoff.address),
              const SizedBox(height: 10),
              Row(
                children: [
                  StatusChip.payment(d),
                  const Spacer(),
                  Text(formatFcfa(d.totalAmount), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PointLine extends StatelessWidget {
  final String label;
  final Color color;
  final String text;

  const _PointLine({required this.label, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: color,
          child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
        const SizedBox(height: 12),
        Center(child: OutlinedButton(onPressed: onRetry, child: const Text('Réessayer'))),
      ],
    );
  }
}
