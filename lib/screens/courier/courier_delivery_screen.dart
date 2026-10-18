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
import '../../widgets/deadline_chip.dart';
import '../../widgets/photos.dart';
import '../../widgets/status_chip.dart';

/// Détail d'une livraison pour le livreur : carte A/B, itinéraires Google Maps, contacts, étapes.
class CourierDeliveryScreen extends StatefulWidget {
  final int deliveryId;

  const CourierDeliveryScreen({super.key, required this.deliveryId});

  @override
  State<CourierDeliveryScreen> createState() => _CourierDeliveryScreenState();
}

class _CourierDeliveryScreenState extends State<CourierDeliveryScreen> with WidgetsBindingObserver {
  Delivery? _delivery;
  String? _error;
  bool _updating = false;
  StreamSubscription<int>? _pushes;
  Timer? _poll;
  Future<void>? _loading;
  String? _supportPhone;
  late final String _shownKey = ShownScreens.deliveryKey(widget.deliveryId);

  @override
  void initState() {
    super.initState();
    ShownScreens.enter(_shownKey);
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Course modifiée par l'agence (notification reçue) : rafraîchissement immédiat.
    _pushes = PushService.deliveryUpdates.listen((id) {
      if (id == widget.deliveryId) _load();
    });
    // Filet de sécurité si la notification n'arrive pas : relecture régulière tant que la course est en cours.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if ((_delivery?.isActive ?? false) && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _load();
      }
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

  /// Retour au premier plan : la course a pu changer pendant que l'app était en arrière-plan.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  /// Relecture de la course ; un chargement déjà en cours est réutilisé.
  Future<void> _load() => _loading ??= _fetch().whenComplete(() => _loading = null);

  Future<void> _fetch() async {
    try {
      final d = await context.read<DeliveryService>().courierDelivery(widget.deliveryId);
      if (mounted) {
        setState(() {
          _delivery = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      // Une relecture ratée ne masque pas la course déjà affichée.
      if (mounted && _delivery == null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _delivery == null) setState(() => _error = 'Une erreur est survenue. Réessayez.');
    }
  }

  /// « Signaler un problème » : appel ou WhatsApp vers l'agence.
  Future<void> _reportProblem(Delivery d) async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = _supportPhone ?? await SupportPhone.load(context.read<ApiClient>());
    if (!mounted) return;
    if (phone == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text("Numéro de l'agence indisponible pour le moment. Réessayez dans un instant."),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Problème sur la livraison ${d.reference}', style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.success,
                child: Icon(Icons.call, color: Colors.white),
              ),
              title: const Text("Appeler l'agence"),
              subtitle: Text(phone),
              onTap: () => Navigator.pop(context, 'call'),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF25D366),
                child: Icon(Icons.chat, color: Colors.white),
              ),
              title: const Text('Écrire sur WhatsApp'),
              onTap: () => Navigator.pop(context, 'whatsapp'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'call') {
      await callPhone(context, phone);
    } else {
      await openWhatsApp(context, phone, message: 'Bonjour, problème sur la livraison ${d.reference} : ');
    }
  }

  Future<void> _advance(String status, String confirmText) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmation'),
        content: Text(confirmText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _updating = true);
    try {
      final d = await context.read<DeliveryService>().updateCourierStatus(_delivery!.id, status);
      if (!mounted) return;
      setState(() => _delivery = d);
      messenger.showSnackBar(SnackBar(content: Text(d.statusLabel), backgroundColor: AppColors.success));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _delivery;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.reference ?? 'Livraison'),
        backgroundColor: AppColors.secondary,
        foregroundColor: AppColors.primary,
      ),
      body: d == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: const TextStyle(color: AppColors.error)),
                      TextButton(onPressed: _load, child: const Text('Réessayer')),
                    ]),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Wrap(spacing: 8, children: [
                    StatusChip.delivery(d),
                    StatusChip(label: d.type.label, color: AppColors.secondary),
                    StatusChip(label: formatKm(d.distanceKm), color: AppColors.info),
                    if (d.deadlineAt != null) DeadlineChip(deadline: d.deadlineAt!, done: !d.isActive),
                  ]),
                  const SizedBox(height: 12),
                  DeliveryMap(pickup: d.pickup, dropoff: d.dropoff, height: 280),
                  const SizedBox(height: 16),
                  _StopCard(
                    letter: 'A',
                    title: 'Récupérer le colis',
                    color: AppColors.success,
                    point: d.pickup,
                    done: d.status == DeliveryStatus.pickedUp || d.status == DeliveryStatus.delivered,
                    navigateLabel: 'Itinéraire vers A',
                  ),
                  _StopCard(
                    letter: 'B',
                    title: 'Livrer au destinataire',
                    color: AppColors.error,
                    point: d.dropoff,
                    done: d.status == DeliveryStatus.delivered,
                    navigateLabel: 'Itinéraire vers B',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Colis', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(d.packageDescription ?? 'Pas de description'),
                          // Photos des articles envoyées par le client : pour reconnaître le colis.
                          if (d.photos.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            PhotoStrip(urls: d.photos, size: 76),
                          ],
                          if (d.notes != null) ...[
                            const SizedBox(height: 10),
                            Text('Instructions', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(d.notes!),
                          ],
                          if (d.scheduledAt != null) ...[
                            const SizedBox(height: 10),
                            Text('À livrer le ${formatDateTime(d.scheduledAt!)}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                          const Divider(height: 24),
                          if (d.parcelAmount != null)
                            // Colis à payer à la livraison : montant à récupérer auprès du destinataire.
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.warning),
                              ),
                              child: Row(children: [
                                const Icon(Icons.payments_outlined, color: AppColors.warning, size: 22),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'À encaisser auprès du destinataire : ${formatFcfa(d.parcelAmount!)}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ]),
                            )
                          else
                            Row(children: [
                              const Icon(Icons.verified, color: AppColors.success, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Livraison payée par Mobile Money (vérifiée par l\'agence). '
                                  'Rien à encaisser auprès du client.',
                                ),
                              ),
                            ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _reportProblem(d),
                    icon: const Icon(Icons.report_problem_outlined, color: AppColors.error),
                    label: const Text('Signaler un problème'),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: d == null ? null : _actionBar(d),
    );
  }

  Widget? _actionBar(Delivery d) {
    final (String? status, String label, String confirm) = switch (d.status) {
      DeliveryStatus.assigned => (
          DeliveryStatus.pickedUp,
          "J'ai récupéré le colis",
          'Confirmez-vous avoir récupéré le colis au point A ?'
        ),
      DeliveryStatus.pickedUp => (
          DeliveryStatus.delivered,
          'Confirmer la livraison',
          // Colis à payer à la livraison : on vérifie l'encaissement avant de clôturer.
          d.parcelAmount != null
              ? 'Avez-vous encaissé ${formatFcfa(d.parcelAmount!)} auprès du destinataire ?\n\n'
                  'Confirmez seulement après avoir reçu le montant et remis le colis.'
              : 'Confirmez-vous avoir remis le colis au destinataire ?'
        ),
      _ => (null, '', ''),
    };
    if (status == null) return null;

    // Prochaine étape : le point A tant que le colis n'est pas récupéré, puis le point B.
    final next = status == DeliveryStatus.pickedUp ? d.pickup : d.dropoff;

    return BottomActionBar(
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => openNavigation(context, next.lat, next.lng),
              icon: const Icon(Icons.navigation_outlined),
              label: Text(status == DeliveryStatus.pickedUp ? 'Vers A' : 'Vers B'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _updating ? null : () => _advance(status, confirm),
                icon: _updating
                    ? const ButtonProgress()
                    : Icon(status == DeliveryStatus.pickedUp ? Icons.inventory_2 : Icons.check_circle),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StopCard extends StatelessWidget {
  final String letter;
  final String title;
  final Color color;
  final DeliveryPoint point;
  final bool done;
  final String navigateLabel;

  const _StopCard({
    required this.letter,
    required this.title,
    required this.color,
    required this.point,
    required this.done,
    required this.navigateLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: done ? AppColors.textHint : color,
                child: done
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text(letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 10),
            Text(point.address, style: const TextStyle(fontSize: 15)),
            if (point.contactName != null || point.contactPhone != null) ...[
              const SizedBox(height: 6),
              Text([point.contactName, point.contactPhone].whereType<String>().join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => openNavigation(context, point.lat, point.lng),
                  icon: const Icon(Icons.navigation),
                  label: Text(navigateLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (point.contactPhone != null) ...[
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Appeler',
                  style: IconButton.styleFrom(backgroundColor: AppColors.success),
                  onPressed: () => callPhone(context, point.contactPhone!),
                  icon: const Icon(Icons.call, color: Colors.white),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}
