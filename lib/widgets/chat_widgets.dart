import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../utils/colors.dart';
import '../utils/formatters.dart';
import '../utils/launchers.dart';
import 'photos.dart';

/// Composants de messagerie partagés par la discussion avec l'agence et celle de la course.

/// Contenu affichable d'un message, quelle que soit sa source.
class BubbleData {
  final bool isMine;
  final bool isSystem;

  /// Auteur affiché au-dessus des bulles des autres (« Livreur », « Agence S-Delivery »…).
  final String? sender;
  final String? body;
  final String? photoUrl;
  final double? lat;
  final double? lng;
  final DateTime createdAt;

  const BubbleData({
    required this.isMine,
    this.isSystem = false,
    this.sender,
    this.body,
    this.photoUrl,
    this.lat,
    this.lng,
    required this.createdAt,
  });

  bool get hasLocation => lat != null && lng != null;
}

/// Message pas encore accepté par le serveur.
class OutgoingMessage {
  final String? body;
  final String? photoPath;
  final double? lat;
  final double? lng;
  bool failed = false;

  /// Identifiant renvoyé par le serveur une fois le message accepté (en attente d'affichage).
  int? sentId;

  OutgoingMessage({this.body, this.photoPath, this.lat, this.lng});

  String get preview => photoPath != null
      ? '📷 Photo'
      : lat != null
          ? '📍 ${body ?? 'Position'}'
          : (body ?? '');
}

const _mineRadius = BorderRadius.only(
  topLeft: Radius.circular(20),
  topRight: Radius.circular(20),
  bottomLeft: Radius.circular(20),
  bottomRight: Radius.circular(6),
);
const _theirsRadius = BorderRadius.only(
  topLeft: Radius.circular(20),
  topRight: Radius.circular(20),
  bottomLeft: Radius.circular(6),
  bottomRight: Radius.circular(20),
);

/// Bulle de message : noire à droite pour mes messages, grise à gauche pour les autres.
class MessageBubble extends StatelessWidget {
  final BubbleData message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.isSystem) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
          child: Text(
            '${m.body ?? ''} · ${formatTime(m.createdAt)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final mine = m.isMine;
    final hasPhoto = m.photoUrl != null;
    final fg = mine ? Colors.white : AppColors.ink;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine && m.sender != null)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 6, bottom: 2),
                child: Text(
                  m.sender!,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
              ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: EdgeInsets.all(hasPhoto ? 4 : 12),
              decoration: BoxDecoration(
                color: mine ? AppColors.ink : AppColors.surface,
                borderRadius: mine ? _mineRadius : _theirsRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasPhoto)
                    GestureDetector(
                      onTap: () => openPhotoViewer(context, [m.photoUrl!]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: m.photoUrl!,
                          width: 230,
                          height: 230,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(width: 230, height: 230, color: AppColors.surfaceStrong),
                        ),
                      ),
                    ),
                  if (m.hasLocation)
                    InkWell(
                      onTap: () => openMapAt(context, m.lat!, m.lng!),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: mine ? AppColors.accent : AppColors.ink,
                            child: Icon(Icons.location_on, color: mine ? AppColors.ink : Colors.white, size: 18),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              m.body ?? 'Position partagée',
                              style: TextStyle(fontWeight: FontWeight.w600, color: fg, decoration: TextDecoration.underline),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (m.body != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(hasPhoto ? 8 : 0, hasPhoto ? 8 : 0, 0, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(m.body!, style: TextStyle(fontSize: 15, color: fg, height: 1.3)),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.only(top: 3, right: hasPhoto ? 8 : 0, bottom: hasPhoto ? 4 : 0),
                    child: Text(
                      formatTime(m.createdAt),
                      style: TextStyle(fontSize: 10.5, color: mine ? Colors.white60 : AppColors.textHint),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bulle d'un message en cours d'envoi, ou non envoyé avec « Renvoyer ».
class OutgoingBubble extends StatelessWidget {
  final OutgoingMessage message;
  final VoidCallback? onRetry;
  final VoidCallback onDiscard;

  const OutgoingBubble({super.key, required this.message, required this.onRetry, required this.onDiscard});

  @override
  Widget build(BuildContext context) {
    final failed = message.failed;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          decoration: BoxDecoration(
            color: failed ? Colors.white : AppColors.ink.withValues(alpha: 0.55),
            borderRadius: _mineRadius,
            border: failed ? Border.all(color: AppColors.error) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  message.preview,
                  style: TextStyle(fontSize: 15, color: failed ? AppColors.ink : Colors.white),
                ),
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
                  padding: EdgeInsets.only(top: 4, bottom: 6),
                  child: Text('Envoi…', style: TextStyle(fontSize: 10.5, color: Colors.white70)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zone de saisie : pièce jointe, texte, bouton d'envoi noir.
class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final String hint;

  /// Réponses rapides proposées au-dessus du champ (« J'arrive », « Je suis devant »…).
  final List<String> quickReplies;
  final ValueChanged<String>? onQuickReply;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onAttach,
    required this.onSend,
    this.hint = 'Écrire un message',
    this.quickReplies = const [],
    this.onQuickReply,
  });

  @override
  Widget build(BuildContext context) {
    final round = OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (quickReplies.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  itemCount: quickReplies.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ActionChip(
                    label: Text(quickReplies[i]),
                    onPressed: sending ? null : () => onQuickReply?.call(quickReplies[i]),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Photo ou position',
                    onPressed: sending ? null : onAttach,
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 28),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: hint,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: round,
                        enabledBorder: round,
                        focusedBorder: round,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: 'Envoyer',
                    onPressed: sending ? null : onSend,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                    ),
                    icon: sending
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choix de la pièce jointe : photo ou position.
Future<String?> pickAttachmentKind(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.surface,
              child: Icon(Icons.photo_camera_outlined, color: AppColors.ink),
            ),
            title: const Text('Photo'),
            onTap: () => Navigator.pop(context, 'photo'),
          ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.surface,
              child: Icon(Icons.location_on_outlined, color: AppColors.ink),
            ),
            title: const Text('Position'),
            onTap: () => Navigator.pop(context, 'location'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
