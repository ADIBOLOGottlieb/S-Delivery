import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/delivery.dart';
import '../../services/api_client.dart';
import '../../services/delivery_service.dart';
import '../../services/push_service.dart';
import '../../services/support_phone.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../utils/launchers.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/delivery_map.dart';
import '../../widgets/photos.dart';
import '../../widgets/status_chip.dart';
import '../chat/chat_screen.dart';
import 'payment_screen.dart';

/// Suivi d'une livraison par le client.
class DeliveryDetailScreen extends StatefulWidget {
  final int deliveryId;

  const DeliveryDetailScreen({super.key, required this.deliveryId});

  /// Photos acceptées par livraison (limite du serveur).
  static const maxPhotos = 6;

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  Delivery? _delivery;
  String? _error;
  bool _busy = false;
  bool _loading = false;
  bool _uploading = false;
  String? _supportPhone;
  Timer? _poll;
  StreamSubscription<int>? _pushes;

  @override
  void initState() {
    super.initState();
    _load();
    // Suivi en direct : relecture régulière tant que la livraison est en cours.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_delivery?.isActive ?? false) _load();
    });
    // Notification reçue pour cette livraison : rafraîchissement immédiat.
    _pushes = PushService.deliveryUpdates.listen((id) {
      if (id == widget.deliveryId) _load();
    });
    SupportPhone.load(context.read<ApiClient>()).then((phone) {
      if (mounted && phone != null) setState(() => _supportPhone = phone);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pushes?.cancel();
    super.dispose();
  }

  /// Relit la livraison sans effacer l'écran : les anciennes données restent affichées pendant le chargement.
  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final d = await context.read<DeliveryService>().getDelivery(widget.deliveryId);
      if (mounted) {
        setState(() {
          _delivery = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      // Échec d'une relecture en arrière-plan : on garde la dernière version connue.
      if (mounted && _delivery == null) setState(() => _error = e.message);
    } catch (e) {
      if (mounted && _delivery == null) setState(() => _error = 'Une erreur est survenue. Réessayez.');
    } finally {
      _loading = false;
    }
  }

  Future<void> _pay() async {
    final updated = await Navigator.of(context).push<Delivery>(
      MaterialPageRoute(builder: (_) => PaymentScreen(delivery: _delivery!)),
    );
    if (updated != null && mounted) setState(() => _delivery = updated);
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la demande ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oui, annuler')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final d = await context.read<DeliveryService>().cancelDelivery(_delivery!.id);
      if (mounted) setState(() => _delivery = d);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      // Statut probablement changé entre-temps (paiement envoyé, livreur assigné…).
      _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Photos des articles ajoutées après la création (tant que le colis n'est pas récupéré).
  Future<void> _addPhotos({required bool multiple}) async {
    final d = _delivery;
    if (d == null) return;
    final remaining = DeliveryDetailScreen.maxPhotos - d.photos.length;
    if (remaining <= 0) return;

    final List<String> paths;
    if (multiple) {
      paths = await pickPhotosFromGallery(limit: remaining);
    } else {
      final path = await pickPhoto(context);
      paths = path == null ? const [] : [path];
    }
    if (paths.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<DeliveryService>();
    setState(() => _uploading = true);
    var sent = 0;
    try {
      for (final path in paths.take(remaining)) {
        final updated = await service.addDeliveryPhoto(d.id, path);
        sent++;
        if (!mounted) return;
        setState(() => _delivery = updated);
      }
      messenger.showSnackBar(SnackBar(
        content: Text(sent > 1 ? '$sent photos ajoutées.' : 'Photo ajoutée.'),
        backgroundColor: AppColors.success,
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text("La photo n'a pas pu être envoyée. Réessayez."),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _delivery;
    return Scaffold(
      appBar: AppBar(title: Text(d?.reference ?? 'Livraison')),
      body: SafeArea(
          top: false,
          child: d == null
              ? Center(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, style: const TextStyle(color: AppColors.error)),
                            TextButton(
                              onPressed: () {
                                setState(() => _error = null);
                                _load();
                              },
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    key: const PageStorageKey('delivery-detail'),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        StatusChip.delivery(d),
                        StatusChip.payment(d),
                        StatusChip(label: d.type.label, color: AppColors.secondary),
                      ]),
                      const SizedBox(height: 16),
                      _PaymentBanner(delivery: d, supportPhone: _supportPhone),
                      const SizedBox(height: 16),
                      DeliveryMap(pickup: d.pickup, dropoff: d.dropoff, height: 220),
                      const SizedBox(height: 16),
                      _PointTile(letter: 'A', color: AppColors.success, title: 'Récupération', point: d.pickup),
                      _PointTile(letter: 'B', color: AppColors.error, title: 'Destination', point: d.dropoff),
                      if (d.photos.isNotEmpty || d.acceptsPhotos) _photosCard(d),
                      if (d.requestId != null)
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppColors.primary,
                              child: Icon(Icons.forum_outlined, color: AppColors.onPrimary),
                            ),
                            title: const Text("Discussion avec l'agence"),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ChatScreen(requestId: d.requestId!)),
                            ),
                          ),
                        ),
                      if (d.courier != null)
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppColors.secondary,
                              child: Icon(Icons.delivery_dining, color: AppColors.primary),
                            ),
                            title: Text('Livreur : ${d.courier!.name}'),
                            subtitle: Text(d.courier!.vehicle ?? ''),
                            trailing: d.courier!.phoneNumber == null
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.call, color: AppColors.success),
                                    onPressed: () => callPhone(context, d.courier!.phoneNumber!),
                                  ),
                          ),
                        ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              if (d.packageDescription != null) _Row('Contenu', d.packageDescription!),
                              if (d.scheduledAt != null) _Row('Programmée', formatDateTime(d.scheduledAt!)),
                              if (d.deadlineAt != null) _Row('À livrer avant', formatDateTime(d.deadlineAt!)),
                              _Row('Distance estimée', formatKm(d.distanceKm)),
                              _Row('Frais de livraison', formatFcfa(d.deliveryFee)),
                              if (d.itemsAmount > 0) _Row('Articles', formatFcfa(d.itemsAmount)),
                              if (d.parcelAmount != null)
                                _Row('À encaisser auprès du destinataire', formatFcfa(d.parcelAmount!)),
                              const Divider(),
                              _Row('Total', formatFcfa(d.totalAmount), bold: true),
                              _Row('Créée le', formatDateTime(d.createdAt)),
                              if (d.deliveredAt != null) _Row('Livrée le', formatDateTime(d.deliveredAt!)),
                              if (d.cancelReason != null) _Row('Annulation', d.cancelReason!),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
      bottomNavigationBar: d == null || !(d.canPay || d.canCancel) ? null : _actions(d),
    );
  }

  /// Photos des articles, avec ajout possible tant que le colis n'est pas récupéré.
  Widget _photosCard(Delivery d) {
    final canAdd = d.acceptsPhotos && d.photos.length < DeliveryDetailScreen.maxPhotos;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Photos des articles', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (d.photos.isNotEmpty)
              PhotoStrip(urls: d.photos)
            else
              Text(
                'Ajoutez des photos pour aider le livreur à reconnaître le colis.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (canAdd) ...[
              const SizedBox(height: 8),
              if (_uploading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Envoi des photos…'),
                  ]),
                )
              else
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _addPhotos(multiple: false),
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Ajouter des photos'),
                    ),
                    TextButton.icon(
                      onPressed: () => _addPhotos(multiple: true),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Plusieurs (galerie)'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Actions du client regroupées en bas de l'écran, à portée du pouce.
  Widget _actions(Delivery d) {
    final cancel = OutlinedButton(
      onPressed: _busy ? null : _cancel,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: const BorderSide(color: AppColors.error),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: const Text('Annuler'),
    );
    if (!d.canPay) return BottomActionBar(children: [cancel]);

    return BottomActionBar(
      children: [
        Row(
          children: [
            if (d.canCancel) ...[cancel, const SizedBox(width: 12)],
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _pay,
                icon: const Icon(Icons.payments_outlined),
                label: Text('Payer ${formatFcfa(d.totalAmount)}'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PaymentBanner extends StatelessWidget {
  final Delivery delivery;
  final String? supportPhone;

  const _PaymentBanner({required this.delivery, this.supportPhone});

  /// Message selon le paiement ET l'avancement de la livraison.
  static (Color, String)? message(Delivery d) {
    if (d.status == DeliveryStatus.cancelled) return null;
    final progress = switch (d.status) {
      DeliveryStatus.assigned => 'Un livreur est en route vers le point de récupération.',
      DeliveryStatus.pickedUp => 'Votre colis est en route vers la destination.',
      DeliveryStatus.delivered => 'Colis livré.',
      _ => 'Un livreur va être assigné.',
    };
    return switch (d.paymentStatus) {
      PaymentStatus.submitted => (
          AppColors.warning,
          d.isActive && !d.canCancel
              ? "Preuve de paiement reçue. L'agence vérifie la transaction.\n"
                  "La demande ne peut plus être annulée depuis l'application : contactez l'agence si besoin."
              : "Preuve de paiement reçue. L'agence vérifie la transaction."
        ),
      PaymentStatus.verified => (AppColors.success, 'Paiement confirmé. $progress'),
      PaymentStatus.rejected => (
          AppColors.error,
          'Paiement refusé${d.latestPayment?.rejectionReason != null ? ' : ${d.latestPayment!.rejectionReason}' : ''}. Renvoyez une preuve valide.'
        ),
      _ => d.isActive
          ? (AppColors.info, 'Payez ${formatFcfa(d.totalAmount)} par Flooz ou Mixx by Yas pour confirmer la demande.')
          : null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final content = message(d);
    if (content == null) return const SizedBox.shrink();
    final (color, text) = content;
    final showCall =
        supportPhone != null && d.paymentStatus == PaymentStatus.submitted && d.isActive && !d.canCancel;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          if (showCall)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => callPhone(context, supportPhone!),
                icon: const Icon(Icons.call),
                label: const Text("Appeler l'agence"),
              ),
            ),
        ],
      ),
    );
  }
}

class _PointTile extends StatelessWidget {
  final String letter;
  final Color color;
  final String title;
  final DeliveryPoint point;

  const _PointTile({required this.letter, required this.color, required this.title, required this.point});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Text(letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([point.address, point.contactName, point.contactPhone].whereType<String>().join('\n')),
        isThreeLine: true,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _Row(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(child: Text(value, style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
