import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/delivery_service.dart';
import '../../utils/colors.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/photos.dart';
import 'chat_screen.dart';

/// Programmation par photo (clients habitués) : photos du colis + quartier, numéro et
/// montant total du colis, tous obligatoires. L'agence programme ensuite la livraison
/// dans la discussion.
class QuickRequestScreen extends StatefulWidget {
  const QuickRequestScreen({super.key});

  static const maxPhotos = 6;

  @override
  State<QuickRequestScreen> createState() => _QuickRequestScreenState();
}

class _QuickRequestScreenState extends State<QuickRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _district = TextEditingController();
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _message = TextEditingController();
  final _photos = <String>[];
  bool _sending = false;
  bool _photoMissing = false;

  @override
  void dispose() {
    for (final c in [_district, _phone, _amount, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final remaining = QuickRequestScreen.maxPhotos - _photos.length;
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text('Choisir dans la galerie (jusqu\'à $remaining)'),
              onTap: () => Navigator.pop(context, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (camera == null) return;

    final List<String> picked;
    if (camera) {
      final path = await pickPhotoFromCamera();
      picked = path == null ? const [] : [path];
    } else {
      picked = await pickPhotosFromGallery(limit: remaining);
    }
    if (mounted && picked.isNotEmpty) {
      setState(() {
        _photos.addAll(picked.take(remaining));
        _photoMissing = false;
      });
    }
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    // Tous les éléments sont obligatoires : sans eux, la demande ne part pas.
    final fieldsOk = _formKey.currentState!.validate();
    setState(() => _photoMissing = _photos.isEmpty);
    if (!fieldsOk || _photos.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Photo, quartier, numéro et montant total du colis sont obligatoires.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    setState(() => _sending = true);
    try {
      final request = await context.read<DeliveryService>().createChatRequest(
            photoPaths: _photos,
            district: _district.text.trim(),
            recipientPhone: _phone.text.trim(),
            parcelAmount: int.parse(_amount.text.trim()),
            message: _message.text.trim(),
          );
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

  static String? _required(String? v, String message) => (v == null || v.trim().isEmpty) ? message : null;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Programmation par photo')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: AppColors.secondary, borderRadius: BorderRadius.circular(20)),
              child: const Row(
                children: [
                  Icon(Icons.add_a_photo, color: AppColors.primary, size: 32),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Photo du colis + quartier, numéro et montant total : l'agence programme la livraison "
                      'avec vous dans la discussion.',
                      style: TextStyle(color: Colors.white, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _Steps(),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('Photos du colis', style: textTheme.titleMedium),
                const Text(' *', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${_photos.length}/${QuickRequestScreen.maxPhotos}', style: textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            LocalPhotoGrid(
              paths: _photos,
              max: QuickRequestScreen.maxPhotos,
              onAdd: _addPhotos,
              onRemove: (i) => setState(() => _photos.removeAt(i)),
            ),
            if (_photoMissing)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Ajoutez au moins une photo du colis.',
                    style: TextStyle(color: AppColors.error, fontSize: 12)),
              ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _district,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Quartier de livraison *',
                hintText: 'Ex. : Agoè Assiyéyé, Bè Kpota…',
                prefixIcon: Icon(Icons.location_city),
              ),
              validator: (v) => _required(v, 'Le quartier est obligatoire'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Numéro du destinataire *',
                hintText: 'Ex. : 90 00 00 00',
                prefixIcon: Icon(Icons.phone),
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.isEmpty) return 'Le numéro est obligatoire';
                if (digits.length < 8) return 'Numéro incomplet (8 chiffres)';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Montant total du colis *',
                suffixText: 'FCFA',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (v) {
                final amount = int.tryParse((v ?? '').trim());
                if (amount == null) return 'Le montant total est obligatoire';
                if (amount <= 0) return 'Montant invalide';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _message,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Précisions (facultatif)',
                hintText: 'Ex. : récupérer à ma boutique, livrer avant 17 h',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        children: [
          ElevatedButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending ? const ButtonProgress() : const Icon(Icons.send_rounded),
            label: const Text("Envoyer à l'agence"),
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.add_a_photo_outlined, 'Photos'),
      (Icons.chat_bubble_outline, 'Discussion'),
      (Icons.payments_outlined, 'Paiement'),
      (Icons.delivery_dining, 'Livraison'),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: i == 0 ? AppColors.primary : AppColors.surface,
                  child: Icon(steps[i].$1, size: 20, color: AppColors.secondary),
                ),
                const SizedBox(height: 6),
                Text(steps[i].$2, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (i < steps.length - 1)
            Container(width: 14, height: 2, margin: const EdgeInsets.only(bottom: 18), color: AppColors.textHint),
        ],
      ],
    );
  }
}
