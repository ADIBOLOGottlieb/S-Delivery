import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/delivery.dart';
import '../../models/product.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/delivery_service.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/bottom_action_bar.dart';

/// Paiement d'une livraison par Flooz ou Mixx by Yas : virement au numéro marchand
/// de l'agence, puis capture d'écran de la transaction, vérifiée par l'agence.
class PaymentScreen extends StatefulWidget {
  final Delivery delivery;

  const PaymentScreen({super.key, required this.delivery});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _refController = TextEditingController();
  late final _phoneController = TextEditingController(text: context.read<AuthService>().user?.phoneNumber);

  late Future<PaymentInfo> _info = context.read<DeliveryService>().paymentInfo();
  String? _method;
  XFile? _screenshot;
  bool _sending = false;

  @override
  void dispose() {
    _refController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _error(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.error));

  /// Moyens de paiement non chargés (réseau) : nouvel essai.
  void _retryInfo() => setState(() => _info = context.read<DeliveryService>().paymentInfo());

  Future<void> _pickScreenshot() async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    } catch (_) {
      if (mounted) _error("Impossible d'ouvrir la galerie. Vérifiez les autorisations de l'application.");
      return;
    }
    if (file != null && mounted) setState(() => _screenshot = file);
  }

  Future<void> _submit() async {
    if (_method == null) return _error('Choisissez Flooz ou Mixx by Yas.');
    if (!_formKey.currentState!.validate()) return;
    if (_screenshot == null) return _error("Ajoutez la capture d'écran de la transaction.");

    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<DeliveryService>();
    setState(() => _sending = true);
    try {
      final updated = await service.submitPayment(
            deliveryId: widget.delivery.id,
            method: _method!,
            transactionRef: _refController.text.trim(),
            payerPhone: _phoneController.text.trim(),
            screenshotPath: _screenshot!.path,
          );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text("Preuve envoyée. Vous serez informé dès que l'agence l'aura vérifiée."),
        backgroundColor: AppColors.success,
      ));
      Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      // Délai dépassé : la preuve a pu arriver. On relit la livraison avant de proposer de renvoyer.
      if (e.timedOut && await _proofReceived(service)) return;
      if (mounted) _error(e.message);
    } catch (_) {
      if (mounted) _error("La preuve n'a pas pu être envoyée. Réessayez.");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Après un délai dépassé : vrai (et écran fermé) si le serveur a bien reçu la preuve.
  Future<bool> _proofReceived(DeliveryService service) async {
    try {
      final d = await service.getDelivery(widget.delivery.id);
      final received = d.paymentStatus == PaymentStatus.submitted || d.paymentStatus == PaymentStatus.verified;
      if (!received || !mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Preuve bien reçue. Vous serez informé dès que l'agence l'aura vérifiée."),
        backgroundColor: AppColors.success,
      ));
      Navigator.of(context).pop(d);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paiement')),
      body: FutureBuilder<PaymentInfo>(
        future: _info,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: AppColors.textHint),
                    const SizedBox(height: 12),
                    Text(
                      error is ApiException
                          ? error.message
                          : 'Impossible de charger les moyens de paiement. Vérifiez votre connexion.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.error),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _retryInfo, child: const Text('Réessayer')),
                  ],
                ),
              ),
            );
          }
          final info = snapshot.data!;
          if (info.methods.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Le paiement mobile n'est pas encore configuré par l'agence. Contactez VOOM Delivery.",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Form(key: _formKey, child: _form(info));
        },
      ),
      bottomNavigationBar: BottomActionBar(
        children: [
          ElevatedButton.icon(
            onPressed: _sending ? null : _submit,
            icon: _sending ? const ButtonProgress() : const Icon(Icons.send_rounded),
            label: const Text('Envoyer la preuve'),
          ),
        ],
      ),
    );
  }

  Widget _form(PaymentInfo info) {
    final selected = info.methods.where((m) => m.method == _method).firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        _AmountCard(amount: widget.delivery.totalAmount, reference: widget.delivery.reference),
        const SizedBox(height: 22),
        const _Step(number: 1, title: 'Choisissez votre moyen de paiement'),
        for (final m in info.methods)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MethodTile(method: m, selected: _method == m.method, onTap: () => setState(() => _method = m.method)),
          ),
        if (selected != null) ...[
          const SizedBox(height: 12),
          const _Step(number: 2, title: 'Envoyez le montant à ce numéro'),
          _MerchantCard(name: info.merchantName, number: selected.merchantNumber),
          if (info.instructions != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(info.instructions!, style: Theme.of(context).textTheme.bodyMedium),
            ),
          const SizedBox(height: 22),
          const _Step(number: 3, title: 'Envoyez la preuve de paiement'),
          TextFormField(
            controller: _refController,
            decoration: const InputDecoration(
              labelText: 'Référence / ID de la transaction',
              helperText: 'Indiquée dans le SMS de confirmation',
              prefixIcon: Icon(Icons.receipt_long),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Référence requise' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Numéro ayant effectué le paiement',
              prefixIcon: Icon(Icons.phone_android),
            ),
            validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 8 ? 'Numéro invalide' : null,
          ),
          const SizedBox(height: 12),
          _ScreenshotPicker(file: _screenshot, onTap: _pickScreenshot),
        ],
      ],
    );
  }
}

/// Montant à payer, en bloc noir et jaune bien visible.
class _AmountCard extends StatelessWidget {
  final int amount;
  final String reference;

  const _AmountCard({required this.amount, required this.reference});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.primary,
            child: Icon(Icons.payments_rounded, color: AppColors.onPrimary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Montant à payer', style: TextStyle(color: Colors.white70)),
                Text(
                  formatFcfa(amount),
                  style: const TextStyle(color: AppColors.primary, fontSize: 28, fontWeight: FontWeight.w800),
                ),
                Text('Livraison $reference', style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Titre d'étape numérotée (1, 2, 3).
class _Step extends StatelessWidget {
  final int number;
  final String title;

  const _Step({required this.number, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppColors.primary,
            child: Text('$number',
                style: const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ],
      ),
    );
  }
}

/// Numéro marchand en grand, avec copie en un appui.
class _MerchantCard extends StatelessWidget {
  final String name;
  final String number;

  const _MerchantCard({required this.name, required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryDark),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.bodyMedium),
                Text(number, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ],
            ),
          ),
          IconButton.filled(
            tooltip: 'Copier le numéro',
            style: IconButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: AppColors.primary),
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: number));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro copié')));
            },
          ),
        ],
      ),
    );
  }
}

/// Zone d'ajout de la capture d'écran, avec aperçu.
class _ScreenshotPicker extends StatelessWidget {
  final XFile? file;
  final VoidCallback onTap;

  const _ScreenshotPicker({required this.file, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: file == null ? AppColors.primaryDark : AppColors.success, width: 1.5),
          ),
          child: file == null
              ? const Column(
                  children: [
                    SizedBox(height: 8),
                    Icon(Icons.add_photo_alternate_outlined, size: 40, color: AppColors.textSecondary),
                    SizedBox(height: 6),
                    Text("Ajouter la capture d'écran", style: TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(height: 8),
                  ],
                )
              : Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(file!.path), height: 240, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 8),
                    const Text('Changer la capture', style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Moyen de paiement sélectionnable.
class _MethodTile extends StatelessWidget {
  final PaymentMethodInfo method;
  final bool selected;
  final VoidCallback onTap;

  const _MethodTile({required this.method, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final mixx = method.method == 'mixx';
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? AppColors.secondary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: mixx ? const Color(0xFFFFD400) : const Color(0xFF0066B3),
                  child: Icon(Icons.phone_iphone, color: mixx ? AppColors.onPrimary : Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(method.label, style: Theme.of(context).textTheme.titleMedium)),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.radio_button_off,
                  color: selected ? AppColors.secondary : AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
