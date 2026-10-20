import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../widgets/ui.dart';
import '../chat/delivery_chat_screen.dart';

/// Détail d'une course pour le livreur : carte A/B, itinéraires, contacts, discussion, étapes et code de remise.
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
    // Course modifiée par l'agence ou nouveau message : rafraîchissement immédiat.
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

  Future<void> _openChat(Delivery d) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DeliveryChatScreen(deliveryId: d.id, courier: true, title: d.client?.name ?? 'Client'),
    ));
    if (mounted) _load();
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
              child: Text('Problème sur la course ${d.reference}', style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: AppColors.surface, child: Icon(Icons.call_outlined, color: AppColors.ink)),
              title: const Text("Appeler l'agence"),
              subtitle: Text(phone),
              onTap: () => Navigator.pop(context, 'call'),
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF25D366), child: Icon(Icons.chat, color: Colors.white)),
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
      await openWhatsApp(context, phone, message: 'Bonjour, problème sur la course ${d.reference} : ');
    }
  }

  Future<void> _advance(String status, String confirmText) async {
    final d = _delivery!;
    String? code;
    if (status == DeliveryStatus.delivered && d.requiresCode) {
      // Le destinataire donne le code à 4 chiffres reçu par le client : preuve de la remise.
      code = await showDialog<String>(context: context, builder: (_) => _CodeDialog(extra: confirmText));
      if (code == null || !mounted) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmation'),
          content: Text(confirmText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmer')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _updating = true);
    try {
      final updated = await context.read<DeliveryService>().updateCourierStatus(d.id, status, code: code);
      if (!mounted) return;
      setState(() => _delivery = updated);
      messenger.showSnackBar(SnackBar(content: Text(updated.statusLabel), backgroundColor: AppColors.success));
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
        title: Text(d?.reference ?? 'Course'),
        actions: [
          if (d != null && (d.chatOpen || d.unreadMessages > 0))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: RoundAction(
                icon: Icons.chat_bubble_outline_rounded,
                tooltip: 'Discussion',
                badge: d.unreadMessages,
                onTap: () => _openChat(d),
              ),
            ),
        ],
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
                padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    StatusChip.delivery(d),
                    StatusChip(label: d.type.label, color: AppColors.ink),
                    StatusChip(label: formatKm(d.distanceKm), color: AppColors.info),
                    if (d.deadlineAt != null) DeadlineChip(deadline: d.deadlineAt!, done: !d.isActive),
                  ]),
                  const SizedBox(height: 14),
                  DeliveryMap(pickup: d.pickup, dropoff: d.dropoff, height: 240),
                  const SizedBox(height: 8),
                  _StopTile(
                    pickup: true,
                    title: 'Récupérer le colis',
                    point: d.pickup,
                    done: d.status == DeliveryStatus.pickedUp || d.status == DeliveryStatus.delivered,
                  ),
                  const Divider(),
                  _StopTile(
                    pickup: false,
                    title: 'Livrer au destinataire',
                    point: d.dropoff,
                    done: d.status == DeliveryStatus.delivered,
                  ),
                  const SectionTitle('Colis'),
                  Text(d.packageDescription ?? 'Pas de description', style: const TextStyle(fontSize: 15)),
                  // Photos des articles envoyées par le client : pour reconnaître le colis.
                  if (d.photos.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    PhotoStrip(urls: d.photos, size: 76),
                  ],
                  if (d.notes != null) ...[
                    const SectionTitle('Instructions'),
                    Text(d.notes!, style: const TextStyle(fontSize: 15)),
                  ],
                  if (d.scheduledAt != null) ...[
                    const SizedBox(height: 10),
                    Text('À livrer le ${formatDateTime(d.scheduledAt!)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: d.parcelAmount != null ? const Color(0xFFFFF4E5) : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      Icon(
                        d.parcelAmount != null ? Icons.payments_outlined : Icons.verified_outlined,
                        color: d.parcelAmount != null ? AppColors.warning : AppColors.success,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          // Colis à payer à la livraison : montant à récupérer auprès du destinataire.
                          d.parcelAmount != null
                              ? 'À encaisser auprès du destinataire : ${formatFcfa(d.parcelAmount!)}'
                              : 'Course déjà payée. Rien à encaisser auprès du client.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  ),
                  if (d.requiresCode && d.isActive) ...[
                    const SizedBox(height: 10),
                    const Row(children: [
                      Icon(Icons.pin_outlined, size: 18, color: AppColors.textSecondary),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'À la remise, demandez le code à 4 chiffres au destinataire.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => _reportProblem(d),
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    icon: const Icon(Icons.report_problem_outlined),
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
          'Confirmez-vous avoir récupéré le colis au point de départ ?'
        ),
      DeliveryStatus.pickedUp => (
          DeliveryStatus.delivered,
          'Colis remis',
          // Colis à payer à la livraison : on vérifie l'encaissement avant de clôturer.
          d.parcelAmount != null
              ? 'Avez-vous encaissé ${formatFcfa(d.parcelAmount!)} auprès du destinataire ? '
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
              label: Text(status == DeliveryStatus.pickedUp ? 'Départ' : 'Arrivée'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14), minimumSize: const Size(0, 56)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _updating ? null : () => _advance(status, confirm),
                child: _updating ? const ButtonProgress() : FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Étape de la course : adresse, contact, itinéraire et appel.
class _StopTile extends StatelessWidget {
  final bool pickup;
  final String title;
  final DeliveryPoint point;
  final bool done;

  const _StopTile({required this.pickup, required this.title, required this.point, required this.done});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: done
                ? const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success)
                : StopDot(pickup: pickup, size: 14),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodySmall),
                Text(point.address, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                if (point.contactName != null || point.contactPhone != null)
                  Text([point.contactName, point.contactPhone].whereType<String>().join(' · '),
                      style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          RoundAction(
            icon: Icons.navigation_outlined,
            tooltip: 'Itinéraire',
            onTap: () => openNavigation(context, point.lat, point.lng),
          ),
          if (point.contactPhone != null) ...[
            const SizedBox(width: 8),
            RoundAction(icon: Icons.call_outlined, tooltip: 'Appeler', onTap: () => callPhone(context, point.contactPhone!)),
          ],
        ],
      ),
    );
  }
}

/// Saisie du code de remise donné par le destinataire.
class _CodeDialog extends StatefulWidget {
  final String extra;

  const _CodeDialog({required this.extra});

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _code.text.length == 4;
    return AlertDialog(
      title: const Text('Code de remise'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Demandez au destinataire le code à 4 chiffres reçu par le client.'),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 14),
            decoration: const InputDecoration(counterText: '', hintText: '• • • •'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => ready ? Navigator.pop(context, _code.text) : null,
          ),
          const SizedBox(height: 12),
          Text(widget.extra, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        TextButton(onPressed: ready ? () => Navigator.pop(context, _code.text) : null, child: const Text('Valider')),
      ],
    );
  }
}
