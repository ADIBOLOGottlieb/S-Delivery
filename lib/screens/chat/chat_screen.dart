import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat.dart';
import '../../services/api_client.dart';
import '../../services/delivery_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/push_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/chat_widgets.dart';
import '../../widgets/photos.dart';
import '../../widgets/ui.dart';
import '../common/location_picker_screen.dart';
import '../home/delivery_detail_screen.dart';

/// Discussion avec l'agence pour une demande par photo (style messagerie).
class ChatScreen extends StatefulWidget {
  final int requestId;
  final ChatRequest? initial;

  const ChatScreen({super.key, required this.requestId, this.initial});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  late ChatRequest? _request = widget.initial;
  String? _error;
  bool _sending = false;
  Timer? _poll;
  StreamSubscription<int>? _pushes;
  late final String _shownKey = ShownScreens.chatKey(widget.requestId);

  /// Incrémenté à chaque message accepté par le serveur : une réponse demandée avant l'envoi est périmée.
  int _generation = 0;

  /// Chargement en cours, partagé par les appels simultanés (poll, push, après envoi).
  Future<void>? _inFlight;
  int _inFlightGeneration = -1;

  /// Messages pas encore affichés depuis le serveur (envoi en cours, échec avec « Renvoyer », ou envoyés en attente).
  final List<OutgoingMessage> _outbox = [];

  @override
  void initState() {
    super.initState();
    ShownScreens.enter(_shownKey);
    _load();
    // Nouvelles réponses de l'agence sans recharger l'écran.
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
    _pushes = PushService.chatUpdates.listen((id) {
      if (id == widget.requestId) _load();
    });
  }

  @override
  void dispose() {
    ShownScreens.leave(_shownKey);
    _poll?.cancel();
    _pushes?.cancel();
    _input.dispose();
    super.dispose();
  }

  /// Recharge la discussion ; un chargement déjà lancé depuis le dernier envoi est réutilisé.
  Future<void> _load() {
    final current = _inFlight;
    if (current != null && _inFlightGeneration == _generation) return current;
    final generation = _generation;
    final future = _fetch(generation);
    _inFlight = future;
    _inFlightGeneration = generation;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  Future<void> _fetch(int generation) async {
    final service = context.read<DeliveryService>();
    try {
      final r = await service.chatRequest(widget.requestId);
      // Seules les réponses demandées avant un envoi plus récent sont ignorées.
      if (!mounted || generation != _generation) return;
      final shown = {for (final m in r.messages) m.id};
      setState(() {
        _request = r;
        _error = null;
        // Message envoyé désormais affiché depuis le serveur : la bulle « Envoi… » disparaît.
        _outbox.removeWhere((m) => m.sentId != null && shown.contains(m.sentId));
      });
    } on ApiException catch (e) {
      if (mounted && _request == null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _request == null) setState(() => _error = 'Une erreur est survenue. Réessayez.');
    }
  }

  Future<void> _send(OutgoingMessage message) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<DeliveryService>();
    setState(() {
      _sending = true;
      message.failed = false;
      if (!_outbox.contains(message)) _outbox.add(message);
    });
    try {
      final sent = await service.sendChatMessage(
        widget.requestId,
        body: message.body,
        photoPath: message.photoPath,
        lat: message.lat,
        lng: message.lng,
      );
      if (!mounted) return;
      // Bulle gardée jusqu'à l'arrivée du message enregistré (pas de trou à l'écran).
      setState(() => message.sentId = sent.id);
      _generation++;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => message.failed = true);
      messenger.showSnackBar(SnackBar(
        content: Text(e is ApiException ? e.message : "Message non envoyé. Touchez « Renvoyer » pour réessayer."),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _sendText() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    // Le texte est gardé dans la bulle en attente : rien n'est perdu si l'envoi échoue.
    _input.clear();
    _send(OutgoingMessage(body: text));
  }

  void _discard(OutgoingMessage message) {
    setState(() => _outbox.remove(message));
    // Texte non envoyé remis dans la zone de saisie, si elle est vide.
    if (message.photoPath == null && message.lat == null && _input.text.isEmpty) {
      _input.text = message.body ?? '';
    }
  }

  Future<void> _attach() async {
    final choice = await pickAttachmentKind(context);
    if (!mounted || choice == null) return;

    if (choice == 'photo') {
      final path = await pickPhoto(context);
      if (path != null && mounted) await _send(OutgoingMessage(photoPath: path));
    } else {
      final place = await Navigator.of(context).push<Place>(
        MaterialPageRoute(builder: (_) => const LocationPickerScreen(title: 'Partager une position')),
      );
      if (place != null && mounted) {
        await _send(OutgoingMessage(body: place.label, lat: place.point.latitude, lng: place.point.longitude));
      }
    }
  }

  static BubbleData _bubble(ChatMessage m) => BubbleData(
        isMine: m.isMine,
        isSystem: m.isSystem,
        sender: 'Agence S-Delivery',
        body: m.body,
        photoUrl: m.photoUrl,
        lat: m.lat,
        lng: m.lng,
        createdAt: m.createdAt,
      );

  @override
  Widget build(BuildContext context) {
    final r = _request;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const IconSquare(Icons.support_agent_rounded, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Agence S-Delivery', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (r != null)
                    Text('${r.reference} · ${r.statusLabel}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
      body: r == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: const TextStyle(color: AppColors.error)),
                      TextButton(onPressed: _load, child: const Text('Réessayer')),
                    ]),
            )
          : Column(
              children: [
                if (r.delivery != null)
                  _DeliveryBanner(delivery: r.delivery!, onChanged: _load)
                else if (r.district != null)
                  _ParcelSummary(request: r),
                Expanded(
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: _outbox.length + r.messages.length,
                    itemBuilder: (context, i) {
                      // Liste inversée : les messages en attente sont tout en bas.
                      if (i < _outbox.length) {
                        final m = _outbox[_outbox.length - 1 - i];
                        return OutgoingBubble(
                          message: m,
                          onRetry: _sending ? null : () => _send(m),
                          onDiscard: () => _discard(m),
                        );
                      }
                      final j = i - _outbox.length;
                      return MessageBubble(message: _bubble(r.messages[r.messages.length - 1 - j]));
                    },
                  ),
                ),
                ChatComposer(controller: _input, sending: _sending, onAttach: _attach, onSend: _sendText),
              ],
            ),
    );
  }
}

/// Rappel des éléments de la programmation par photo (quartier, numéro, montant).
class _ParcelSummary extends StatelessWidget {
  final ChatRequest request;

  const _ParcelSummary({required this.request});

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Flexible(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          ],
        );

    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          item(Icons.location_city_outlined, request.district!),
          if (request.recipientPhone != null) item(Icons.phone_outlined, request.recipientPhone!),
          if (request.parcelAmount != null) item(Icons.payments_outlined, formatFcfa(request.parcelAmount!)),
        ],
      ),
    );
  }
}

/// Livraison programmée par l'agence : accès direct au paiement et au suivi.
class _DeliveryBanner extends StatelessWidget {
  final ScheduledDelivery delivery;
  final VoidCallback onChanged;

  const _DeliveryBanner({required this.delivery, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Future<void> open() async {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryDetailScreen(deliveryId: delivery.id)));
      onChanged();
    }

    return Material(
      color: AppColors.ink,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              const Icon(Icons.local_shipping_outlined, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Livraison ${delivery.reference} · ${formatFcfa(delivery.totalAmount)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                    Text(delivery.statusLabel, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.ink,
                  minimumSize: const Size(0, 38),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: open,
                child: Text(delivery.canPay ? 'Payer' : 'Suivre'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
