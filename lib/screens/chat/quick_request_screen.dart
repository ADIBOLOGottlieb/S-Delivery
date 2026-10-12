import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/delivery_service.dart';
import '../../utils/colors.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/photos.dart';
import 'chat_screen.dart';

/// Programmation par photo (clients habitués) : une photo du colis suffit.
/// Pensé pour les commerçants qui lisent peu : gros boutons à icônes, aucun champ à remplir.
/// L'agence complète quartier, numéro et montant dans la discussion.
class QuickRequestScreen extends StatefulWidget {
  const QuickRequestScreen({super.key});

  static const maxPhotos = 6;

  @override
  State<QuickRequestScreen> createState() => _QuickRequestScreenState();
}

class _QuickRequestScreenState extends State<QuickRequestScreen> {
  final _photos = <String>[];
  bool _sending = false;

  int get _remaining => QuickRequestScreen.maxPhotos - _photos.length;

  Future<void> _camera() async {
    final path = await pickPhotoFromCamera();
    if (mounted && path != null) setState(() => _photos.add(path));
  }

  Future<void> _gallery() async {
    final picked = await pickPhotosFromGallery(limit: _remaining);
    if (mounted && picked.isNotEmpty) setState(() => _photos.addAll(picked.take(_remaining)));
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final request = await context.read<DeliveryService>().createChatRequest(photoPaths: _photos);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChatScreen(requestId: request.id, initial: request)),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhotos = _photos.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(title: const Text('Programmation par photo')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '📦  Prenez le colis en photo',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            "C'est tout : l'agence vous appelle pour le reste.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          if (_remaining > 0)
            Row(
              children: [
                Expanded(
                  child: _BigButton(
                    icon: Icons.photo_camera,
                    label: 'Photo',
                    background: AppColors.primary,
                    foreground: AppColors.onPrimary,
                    onTap: _sending ? null : _camera,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _BigButton(
                    icon: Icons.photo_library,
                    label: 'Galerie',
                    background: AppColors.secondary,
                    foreground: AppColors.primary,
                    onTap: _sending ? null : _gallery,
                  ),
                ),
              ],
            ),
          if (hasPhotos) ...[
            const SizedBox(height: 24),
            LocalPhotoGrid(
              paths: _photos,
              max: _photos.length, // l'ajout se fait avec les gros boutons
              onAdd: () {},
              onRemove: (i) => setState(() => _photos.removeAt(i)),
            ),
          ],
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        children: [
          SizedBox(
            height: 58,
            child: ElevatedButton.icon(
              onPressed: !hasPhotos || _sending ? null : _send,
              icon: _sending ? const ButtonProgress() : const Icon(Icons.send_rounded, size: 26),
              label: Text(
                hasPhotos ? 'Envoyer' : 'Prenez une photo',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gros bouton carré à icône, lisible sans savoir lire.
class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  const _BigButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(24),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 150,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 64, color: foreground),
                const SizedBox(height: 8),
                Text(label, style: TextStyle(color: foreground, fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
