import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
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
import '../../utils/launchers.dart';
import '../../widgets/photos.dart';
import '../common/location_picker_screen.dart';
import '../home/delivery_detail_screen.dart';

/// Discussion avec l'agence pour une demande rapide (style messagerie).
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
  final List<_OutgoingMessage> _outbox = [];

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

  Future<void> _send(_OutgoingMessage message) async {
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
    _send(_OutgoingMessage(body: text));
  }

  void _discard(_OutgoingMessage message) {
    setState(() => _outbox.remove(message));
    // Texte non envoyé remis dans la zone de saisie, si elle est vide.
    if (message.photoPath == null && message.lat == null && _input.text.isEmpty) {
      _input.text = message.body ?? '';
    }
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              _AttachOption(icon: Icons.photo_camera, label: 'Photo', color: AppColors.primaryDark, value: 'photo'),
              _AttachOption(icon: Icons.location_on, label: 'Position', color: AppColors.success, value: 'location'),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == 'photo') {
      final path = await pickPhoto(context);
      if (path != null && mounted) await _send(_OutgoingMessage(photoPath: path));
    } else {
      final place = await Navigator.of(context).push<Place>(
        MaterialPageRoute(builder: (_) => const LocationPickerScreen(title: 'Partager une position')),
      );
      if (place != null && mounted) {
        await _send(_OutgoingMessage(body: place.label, lat: place.point.latitude, lng: place.point.longitude));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _request;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.support_agent, color: AppColors.onPrimary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Agence VOOM', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (r != null)
                    Text('${r.reference} · ${r.statusLabel}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    itemCount: _outbox.length + r.messages.length,
                    itemBuilder: (context, i) {
                      // Liste inversée : les messages en attente sont tout en bas.
                      if (i < _outbox.length) {
                        final m = _outbox[_outbox.length - 1 - i];
                        return _OutgoingBubble(
                          message: m,
                          onRetry: _sending ? null : () => _send(m),
                          onDiscard: () => _discard(m),
                        );
                      }
                      final j = i - _outbox.length;
                      return _Bubble(message: r.messages[r.messages.length - 1 - j]);
                    },
                  ),
                ),
                _Composer(controller: _input, sending: _sending, onAttach: _attach, onSend: _sendText),
              ],
            ),
    );
  }
}

/// Message du client pas encore accepté par le serveur.
class _OutgoingMessage {
  final String? body;
  final String? photoPath;
  final double? lat;
  final double? lng;
  bool failed = false;

  /// Identifiant renvoyé par le serveur une fois le message accepté (en attente d'affichage).
  int? sentId;

  _OutgoingMessage({this.body, this.photoPath, this.lat, this.lng});

  String get preview => photoPath != null
      ? '📷 Photo'
      : lat != null
          ? '📍 ${body ?? 'Position'}'
          : (body ?? '');
}

/// Bulle d'un message en cours d'envoi, ou non envoyé avec « Renvoyer ».
class _OutgoingBubble extends StatelessWidget {
  final _OutgoingMessage message;
  final VoidCallback? onRetry;
  final VoidCallback onDiscard;

  const _OutgoingBubble({required this.message, required this.onRetry, required this.onDiscard});

  @override
  Widget build(BuildContext context) {
    final failed = message.failed;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: failed ? 0.35 : 0.6),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
            border: failed ? Border.all(color: AppColors.error) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(message.preview, style: const TextStyle(fontSize: 15)),
              ),
              if (failed)
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: AppColors.error),
                    const SizedBox(width: 4),
                    const Text('Non envoyé', style: TextStyle(fontSize: 12, color: AppColors.error)),
                    TextButton(onPressed: onRetry, child: const Text('Renvoyer')),
                    TextButton(onPressed: onDiscard, child: const Text('Supprimer')),
                  ],
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: Text('Envoi…', style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String value;

  const _AttachOption({required this.icon, required this.label, required this.color, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(context, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              CircleAvatar(radius: 28, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 28)),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
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
            Icon(icon, size: 16, color: AppColors.primaryDark),
            const SizedBox(width: 4),
            Flexible(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          ],
        );

    return Container(
      width: double.infinity,
      color: AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          item(Icons.location_city, request.district!),
          if (request.recipientPhone != null) item(Icons.phone, request.recipientPhone!),
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
      color: AppColors.primary,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              const Icon(Icons.local_shipping, color: AppColors.onPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Livraison ${delivery.reference} · ${formatFcfa(delivery.totalAmount)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(delivery.statusLabel, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: AppColors.primary,
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

class _Bubble extends StatelessWidget {
  final ChatMessage message;

  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: AppColors.card.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
          child: Text(m.body ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
        ),
      );
    }

    final mine = m.isMine;
    final hasPhoto = m.photoUrl != null;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: EdgeInsets.all(hasPhoto ? 4 : 10),
          decoration: BoxDecoration(
            color: mine ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasPhoto)
                GestureDetector(
                  onTap: () => openPhotoViewer(context, [m.photoUrl!]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CachedNetworkImage(
                      imageUrl: m.photoUrl!,
                      width: 230,
                      height: 230,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(width: 230, height: 230, color: AppColors.surface),
                    ),
                  ),
                ),
              if (m.hasLocation)
                InkWell(
                  onTap: () => openMapAt(context, m.lat!, m.lng!),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.success,
                        child: Icon(Icons.location_on, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(m.body ?? 'Position partagée',
                            style: const TextStyle(fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                      ),
                    ],
                  ),
                )
              else if (m.body != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(hasPhoto ? 6 : 0, hasPhoto ? 6 : 0, 0, 0),
                  child: Align(alignment: Alignment.centerLeft, child: Text(m.body!, style: const TextStyle(fontSize: 15))),
                ),
              Padding(
                padding: EdgeInsets.only(top: 2, right: hasPhoto ? 6 : 0),
                child: Text(formatTime(m.createdAt), style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  const _Composer({required this.controller, required this.sending, required this.onAttach, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(28)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Photo ou position',
                      onPressed: sending ? null : onAttach,
                      icon: const Icon(Icons.add_circle_outline, color: AppColors.textSecondary),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 50,
              height: 50,
              child: FloatingActionButton(
                heroTag: null,
                elevation: 1,
                tooltip: 'Envoyer',
                onPressed: sending ? null : onSend,
                backgroundColor: AppColors.secondary,
                foregroundColor: AppColors.primary,
                child: sending
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary))
                    : const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
