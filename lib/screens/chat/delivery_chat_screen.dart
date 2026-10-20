import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/delivery_message.dart';
import '../../services/api_client.dart';
import '../../services/delivery_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/push_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/colors.dart';
import '../../widgets/chat_widgets.dart';
import '../../widgets/photos.dart';
import '../common/location_picker_screen.dart';

/// Discussion d'une course entre le client, le livreur et l'agence (texte, photo, position).
/// [courier] : ouverte par le livreur (sinon par le client).
class DeliveryChatScreen extends StatefulWidget {
  final int deliveryId;
  final bool courier;

  /// Nom de l'autre partie, affiché en titre (« Kossi », « Ama »…).
  final String? title;

  const DeliveryChatScreen({super.key, required this.deliveryId, this.courier = false, this.title});

  @override
  State<DeliveryChatScreen> createState() => _DeliveryChatScreenState();
}

class _DeliveryChatScreenState extends State<DeliveryChatScreen> {
  final _input = TextEditingController();
  DeliveryThread? _thread;
  String? _error;
  bool _sending = false;
  Timer? _poll;
  StreamSubscription<int>? _pushes;
  late final String _shownKey = ShownScreens.deliveryChatKey(widget.deliveryId);

  /// Incrémenté à chaque message accepté : une réponse demandée avant l'envoi est périmée.
  int _generation = 0;
  Future<void>? _inFlight;
  int _inFlightGeneration = -1;

  /// Messages pas encore affichés depuis le serveur (envoi en cours, échec avec « Renvoyer »…).
  final List<OutgoingMessage> _outbox = [];

  List<String> get _quickReplies => widget.courier
      ? const ["J'arrive dans 5 min", 'Je suis devant', 'Où êtes-vous exactement ?', 'Je vous appelle']
      : const ['Je suis là', 'Le portail est ouvert', 'Appelez-moi en arrivant', 'Merci !'];

  @override
  void initState() {
    super.initState();
    ShownScreens.enter(_shownKey);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _load();
    });
    _pushes = PushService.deliveryChatUpdates.listen((id) {
      if (id == widget.deliveryId) _load();
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
      final thread = await service.deliveryThread(widget.deliveryId, courier: widget.courier);
      if (!mounted || generation != _generation) return;
      final shown = {for (final m in thread.messages) m.id};
      setState(() {
        _thread = thread;
        _error = null;
        _outbox.removeWhere((m) => m.sentId != null && shown.contains(m.sentId));
      });
    } on ApiException catch (e) {
      if (mounted && _thread == null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _thread == null) setState(() => _error = 'Une erreur est survenue. Réessayez.');
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
      final sent = await service.sendDeliveryMessage(
        widget.deliveryId,
        courier: widget.courier,
        body: message.body,
        photoPath: message.photoPath,
        lat: message.lat,
        lng: message.lng,
      );
      if (!mounted) return;
      setState(() => message.sentId = sent.id);
      _generation++;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => message.failed = true);
      messenger.showSnackBar(SnackBar(
        content: Text(e is ApiException ? e.message : 'Message non envoyé. Touchez « Renvoyer » pour réessayer.'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _sendText([String? quick]) {
    final text = (quick ?? _input.text).trim();
    if (text.isEmpty) return;
    if (quick == null) _input.clear();
    _send(OutgoingMessage(body: text));
  }

  void _discard(OutgoingMessage message) {
    setState(() => _outbox.remove(message));
    if (message.photoPath == null && message.lat == null && _input.text.isEmpty) _input.text = message.body ?? '';
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

  static BubbleData _bubble(DeliveryMessage m) => BubbleData(
        isMine: m.isMine,
        isSystem: m.isSystem,
        sender: m.from == 'agency' ? m.senderLabel : (m.senderName ?? m.senderLabel),
        body: m.body,
        photoUrl: m.photoUrl,
        lat: m.lat,
        lng: m.lng,
        createdAt: m.createdAt,
      );

  @override
  Widget build(BuildContext context) {
    final t = _thread;
    final open = t?.open ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title ?? (widget.courier ? 'Client' : 'Votre livreur')),
            Text(
              widget.courier ? 'Discussion de la course' : 'Livreur et agence S-Delivery',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: t == null
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
                Expanded(
                  child: t.messages.isEmpty && _outbox.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              widget.courier
                                  ? 'Écrivez au client pour préciser le lieu de récupération ou de remise.'
                                  : 'Écrivez à votre livreur : repère, portail, étage… Il reçoit une notification.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          itemCount: _outbox.length + t.messages.length,
                          itemBuilder: (context, i) {
                            if (i < _outbox.length) {
                              final m = _outbox[_outbox.length - 1 - i];
                              return OutgoingBubble(
                                message: m,
                                onRetry: _sending ? null : () => _send(m),
                                onDiscard: () => _discard(m),
                              );
                            }
                            final j = i - _outbox.length;
                            return MessageBubble(message: _bubble(t.messages[t.messages.length - 1 - j]));
                          },
                        ),
                ),
                if (open)
                  ChatComposer(
                    controller: _input,
                    sending: _sending,
                    onAttach: _attach,
                    onSend: _sendText,
                    quickReplies: _quickReplies,
                    onQuickReply: _sendText,
                  )
                else
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Discussion fermée : la course est terminée.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
