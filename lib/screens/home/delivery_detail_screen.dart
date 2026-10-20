import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/delivery.dart';
import '../../services/api_client.dart';
import '../../services/delivery_service.dart';
import '../../services/push_service.dart';
import '../../services/support_phone.dart';
import '../../utils/app_navigator.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../utils/launchers.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/delivery_map.dart';
import '../../widgets/photos.dart';
import '../../widgets/ui.dart';
import '../../widgets/user_avatar.dart';
import '../chat/chat_screen.dart';
import '../chat/delivery_chat_screen.dart';
import 'home_screen.dart';
import 'payment_screen.dart';

/// Suivi d'une livraison par le client : carte en direct, étape en cours, code de remise, livreur, discussion.
class DeliveryDetailScreen extends StatefulWidget {
  final int deliveryId;

  const DeliveryDetailScreen({super.key, required this.deliveryId});

  /// Photos acceptées par livraison (limite du serveur).
  static const maxPhotos = 6;

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> with WidgetsBindingObserver {
  Delivery? _delivery;
  String? _error;
  bool _busy = false;
  bool _loading = false;
  bool _uploading = false;
  String? _supportPhone;
  Timer? _poll;
  StreamSubscription<int>? _pushes;
  late final String _shownKey = ShownScreens.deliveryKey(widget.deliveryId);

  @override
  void initState() {
    super.initState();
    ShownScreens.enter(_shownKey);
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Suivi en direct : relecture rapprochée pendant la course (position du livreur), plus espacée sinon.
    _poll = Timer.periodic(const Duration(seconds: 10), (tick) {
      final d = _delivery;
      if (d == null || !d.isActive) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      if (d.isInProgress || tick.tick.isEven) _load();
    });
    // Notification reçue pour cette livraison (statut ou message) : rafraîchissement immédiat.
    _pushes = PushService.deliveryUpdates.listen((id) {
      if (id == widget.deliveryId) _load();
    });
    SupportPhone.load(context.read<ApiClient>()).then((phone) {
      if (mounted && phone != null) setState(() => _supportPhone = phone);
    });
  }

  @override
  void dispose() {
    ShownScreens.leave(_shownKey);
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _pushes?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
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
    _load();
  }

  Future<void> _openChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DeliveryChatScreen(deliveryId: widget.deliveryId)),
    );
    if (mounted) _load();
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la livraison ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Oui, annuler'),
          ),
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
    final top = MediaQuery.paddingOf(context).top;

    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Livraison')),
        body: Center(
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
        ),
      );
    }

    final screen = MediaQuery.sizeOf(context).height;
    return Scaffold(
      body: Stack(
        children: [
          // Carte plein écran, cadrée sur la partie visible au-dessus de la feuille.
          Positioned.fill(
            child: DeliveryMap(
              pickup: d.pickup,
              dropoff: d.dropoff,
              courier: d.courier?.location?.latLng,
              interactive: true,
              height: double.infinity,
              fitPadding: EdgeInsets.fromLTRB(56, top + 72, 56, screen * 0.62 + 32),
            ),
          ),
          Positioned(
            left: 12,
            top: top + 8,
            child: IconButton.filled(
              tooltip: 'Retour',
              style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink, elevation: 2),
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.62,
            minChildSize: 0.45,
            maxChildSize: 0.94,
            builder: (context, controller) => DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 20, offset: Offset(0, -4))],
              ),
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  children: _sheet(d),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: d.canPay
          ? BottomActionBar(
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : _pay,
                  child: Text('Payer ${formatFcfa(d.totalAmount)}'),
                ),
              ],
            )
          : null,
    );
  }

  List<Widget> _sheet(Delivery d) {
    final textTheme = Theme.of(context).textTheme;
    final banner = _PaymentBanner.message(d);
    return [
      Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: AppColors.surfaceStrong, borderRadius: BorderRadius.circular(2)),
        ),
      ),
      Text(ActiveDeliveryCard.headline(d), style: textTheme.headlineMedium),
      const SizedBox(height: 4),
      Text('${d.reference} · ${d.statusLabel}', style: textTheme.bodyMedium),
      if (d.status != DeliveryStatus.cancelled) ...[
        const SizedBox(height: 14),
        ProgressSteps(step: d.progressStep),
      ],
      if (banner != null) ...[
        const SizedBox(height: 16),
        _PaymentBanner(delivery: d, supportPhone: _supportPhone),
      ],
      if (d.dropoffCode != null && d.isActive) ...[
        const SizedBox(height: 16),
        _CodeCard(delivery: d),
      ],
      if (d.courier != null) ...[
        const SizedBox(height: 16),
        _CourierCard(
          courier: d.courier!,
          unread: d.unreadMessages,
          onChat: d.chatOpen || d.unreadMessages > 0 ? _openChat : null,
        ),
      ] else if (d.chatOpen) ...[
        const SizedBox(height: 8),
        ListRow(
          icon: Icons.chat_bubble_outline_rounded,
          title: "Écrire à l'agence",
          subtitle: 'Une question sur cette livraison ?',
          trailing: d.unreadMessages > 0 ? CountBadge(count: d.unreadMessages) : null,
          onTap: _openChat,
        ),
      ],
      if (d.canRate || d.rating != null) ...[
        const SizedBox(height: 16),
        _RatingCard(delivery: d, onRated: (updated) => setState(() => _delivery = updated)),
      ],
      const SectionTitle('Trajet'),
      RouteStops(
        pickup: d.pickup.address,
        dropoff: d.dropoff.address,
        pickupLabel: ['Départ', d.pickup.contactName].whereType<String>().join(' · '),
        dropoffLabel: ['Arrivée', d.dropoff.contactName].whereType<String>().join(' · '),
        maxLines: 2,
      ),
      if (d.photos.isNotEmpty || d.acceptsPhotos) ...[
        const SectionTitle('Photos des articles'),
        _photos(d),
      ],
      if (d.requestId != null) ...[
        const SizedBox(height: 8),
        ListRow(
          icon: Icons.forum_outlined,
          title: 'Demande par photo',
          subtitle: "Discussion avec l'agence à l'origine de cette course",
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(requestId: d.requestId!))),
        ),
      ],
      const SectionTitle('Détails'),
      if (d.packageDescription != null) InfoRow('Contenu', d.packageDescription!),
      if (d.scheduledAt != null) InfoRow('Programmée', formatDateTime(d.scheduledAt!)),
      if (d.deadlineAt != null) InfoRow('À livrer avant', formatDateTime(d.deadlineAt!)),
      InfoRow('Distance estimée', formatKm(d.distanceKm)),
      InfoRow('Frais de livraison', formatFcfa(d.deliveryFee)),
      if (d.itemsAmount > 0) InfoRow('Articles', formatFcfa(d.itemsAmount)),
      if (d.parcelAmount != null) InfoRow('À encaisser auprès du destinataire', formatFcfa(d.parcelAmount!)),
      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider()),
      InfoRow('Total', formatFcfa(d.totalAmount), bold: true),
      InfoRow('Paiement', d.paymentStatusLabel),
      InfoRow('Créée le', formatDateTime(d.createdAt)),
      if (d.deliveredAt != null) InfoRow('Livrée le', formatDateTime(d.deliveredAt!)),
      if (d.cancelReason != null) InfoRow('Annulation', d.cancelReason!),
      if (d.canCancel) ...[
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _busy ? null : _cancel,
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          icon: const Icon(Icons.close_rounded),
          label: const Text('Annuler la livraison'),
        ),
      ],
    ];
  }

  /// Photos des articles, avec ajout possible tant que le colis n'est pas récupéré.
  Widget _photos(Delivery d) {
    final canAdd = d.acceptsPhotos && d.photos.length < DeliveryDetailScreen.maxPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (d.photos.isNotEmpty)
          PhotoStrip(urls: d.photos)
        else
          Text('Ajoutez des photos pour aider le livreur à reconnaître le colis.',
              style: Theme.of(context).textTheme.bodyMedium),
        if (canAdd) ...[
          const SizedBox(height: 10),
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
                FilledButton.icon(
                  onPressed: () => _addPhotos(multiple: false),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Ajouter'),
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
    );
  }
}

/// Code de remise : chiffres en grand, à donner au livreur ou à transmettre au destinataire.
class _CodeCard extends StatelessWidget {
  final Delivery delivery;

  const _CodeCard({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final code = d.dropoffCode!;
    final recipientPhone = d.dropoff.contactPhone;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Code de remise', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const Icon(Icons.verified_user_outlined, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final digit in code.split(''))
                Container(
                  width: 48,
                  height: 56,
                  margin: const EdgeInsets.only(right: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Text(digit, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Le livreur vous le demandera à la remise du colis. '
            "Si quelqu'un d'autre le reçoit, transmettez-lui ce code.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (recipientPhone != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => sendSms(
                context,
                recipientPhone,
                'S-Delivery : votre colis ${d.reference} arrive. Code de remise à donner au livreur : $code',
              ),
              icon: const Icon(Icons.sms_outlined),
              label: const Text('Envoyer au destinataire'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Livreur assigné : photo, nom, véhicule, discussion et appel.
class _CourierCard extends StatelessWidget {
  final Person courier;
  final int unread;
  final VoidCallback? onChat;

  const _CourierCard({required this.courier, required this.unread, required this.onChat});

  @override
  Widget build(BuildContext context) {
    final c = courier;
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Avatar(url: c.avatarUrl, initial: c.initial, radius: 28),
            if (c.location != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.two_wheeler_rounded, size: 13, color: AppColors.ink),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text(
                [c.vehicle ?? 'Livreur S-Delivery', if (c.location != null) 'en direct'].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (onChat != null) RoundAction(icon: Icons.chat_bubble_outline_rounded, tooltip: 'Message', onTap: onChat, badge: unread),
        if (c.phoneNumber != null) ...[
          const SizedBox(width: 8),
          RoundAction(icon: Icons.call_outlined, tooltip: 'Appeler', onTap: () => callPhone(context, c.phoneNumber!)),
        ],
      ],
    );
  }
}

/// Note du livreur après la livraison (ou rappel de la note donnée).
class _RatingCard extends StatefulWidget {
  final Delivery delivery;
  final ValueChanged<Delivery> onRated;

  const _RatingCard({required this.delivery, required this.onRated});

  @override
  State<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<_RatingCard> {
  final _comment = TextEditingController();
  int _stars = 0;
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final d = await context.read<DeliveryService>().rateDelivery(widget.delivery.id, rating: _stars, comment: _comment.text);
      if (!mounted) return;
      widget.onRated(d);
      messenger.showSnackBar(const SnackBar(content: Text('Merci pour votre avis !'), backgroundColor: AppColors.success));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.delivery;
    final rated = d.rating;
    final stars = rated ?? _stars;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rated == null ? 'Comment s\'est passée la livraison ?' : 'Votre note',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i étoile${i > 1 ? 's' : ''}',
                  onPressed: rated == null && !_sending ? () => setState(() => _stars = i) : null,
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, size: 34),
                  color: AppColors.ink,
                  disabledColor: AppColors.ink,
                ),
            ],
          ),
          if (rated != null && d.ratingComment != null)
            Text('« ${d.ratingComment} »', style: Theme.of(context).textTheme.bodyMedium),
          if (rated == null && _stars > 0) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(hintText: 'Un commentaire pour le livreur ? (facultatif)', fillColor: Colors.white),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _sending ? null : _send,
              child: _sending ? const ButtonProgress() : const Text('Envoyer mon avis'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentBanner extends StatelessWidget {
  final Delivery delivery;
  final String? supportPhone;

  const _PaymentBanner({required this.delivery, this.supportPhone});

  /// Message selon le paiement ET l'avancement de la livraison.
  static (IconData, String)? message(Delivery d) {
    if (d.status == DeliveryStatus.cancelled) return null;
    return switch (d.paymentStatus) {
      PaymentStatus.submitted => (
          Icons.hourglass_top_rounded,
          d.isActive && !d.canCancel
              ? "Preuve de paiement reçue : l'agence vérifie la transaction. "
                  "La livraison ne peut plus être annulée depuis l'application."
              : "Preuve de paiement reçue : l'agence vérifie la transaction."
        ),
      PaymentStatus.rejected => (
          Icons.error_outline_rounded,
          'Paiement refusé${d.latestPayment?.rejectionReason != null ? ' : ${d.latestPayment!.rejectionReason}' : ''}. Payez à nouveau.'
        ),
      PaymentStatus.verified => d.status == DeliveryStatus.pending
          ? (Icons.check_circle_outline_rounded, 'Paiement confirmé. Un livreur va être assigné.')
          : null,
      _ => d.isActive
          ? (Icons.payments_outlined, 'Payez ${formatFcfa(d.totalAmount)} en Flooz, Mixx by Yas ou par carte pour confirmer la course.')
          : null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final content = message(d);
    if (content == null) return const SizedBox.shrink();
    final (icon, text) = content;
    final rejected = d.paymentStatus == PaymentStatus.rejected;
    final showCall = supportPhone != null && d.paymentStatus == PaymentStatus.submitted && d.isActive && !d.canCancel;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: rejected ? AppColors.error.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: rejected ? AppColors.error : AppColors.ink),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.35))),
            ],
          ),
          if (showCall)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => callPhone(context, supportPhone!),
                icon: const Icon(Icons.call_outlined),
                label: const Text("Appeler l'agence"),
              ),
            ),
        ],
      ),
    );
  }
}
