import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/delivery.dart';
import '../../models/payment.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/delivery_service.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/ui.dart';

/// Paiement d'une livraison :
/// - en ligne (Flooz, Mixx by Yas, carte) quand l'agence a activé un agrégateur, avec confirmation automatique ;
/// - sinon (ou en repli) virement au numéro marchand puis capture d'écran vérifiée par l'agence.
/// Renvoie la livraison à jour via Navigator.pop.
class PaymentScreen extends StatefulWidget {
  final Delivery delivery;

  const PaymentScreen({super.key, required this.delivery});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> with WidgetsBindingObserver {
  late Future<PaymentInfo> _info = context.read<DeliveryService>().paymentInfo();
  late final _phone = TextEditingController(text: context.read<AuthService>().user?.phoneNumber);

  String? _method;
  bool _manual = false;
  bool _starting = false;

  /// Paiement en ligne lancé : en attente de la validation par le client.
  CheckoutResult? _pending;
  bool _failed = false;
  Timer? _poll;
  DateTime? _pendingSince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _phone.dispose();
    super.dispose();
  }

  /// Retour dans l'app après la page de paiement : vérification immédiate.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pending != null) _check();
  }

  void _error(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.error));

  Future<void> _start() async {
    if (_method == null) return _error('Choisissez un moyen de paiement.');
    final phone = _phone.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 8) return _error('Indiquez le numéro qui va payer.');

    setState(() => _starting = true);
    try {
      final result = await context.read<DeliveryService>().checkout(widget.delivery.id, method: _method!, phone: phone);
      if (!mounted) return;
      setState(() {
        _pending = result;
        _failed = false;
        _pendingSince = DateTime.now();
      });
      if (result.opensPage) await _openPage(result.redirectUrl!);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
    } on ApiException catch (e) {
      if (mounted) _error(e.message);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openPage(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) _error('Impossible d\'ouvrir la page de paiement.');
    } catch (_) {
      if (mounted) _error('Impossible d\'ouvrir la page de paiement.');
    }
  }

  bool _checking = false;

  Future<void> _check() async {
    final pending = _pending;
    if (pending == null || _checking) return;
    _checking = true;
    try {
      final r = await context.read<DeliveryService>().paymentStatus(widget.delivery.id, pending.paymentId);
      if (!mounted) return;
      if (r.status == 'verified') {
        _poll?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Paiement confirmé. Un livreur va être assigné.'),
          backgroundColor: AppColors.success,
        ));
        Navigator.of(context).pop(r.delivery);
      } else if (r.status == 'failed' || r.status == 'rejected') {
        _poll?.cancel();
        setState(() {
          _pending = null;
          _failed = true;
        });
      } else if (_pendingSince != null && DateTime.now().difference(_pendingSince!) > const Duration(minutes: 12)) {
        _poll?.cancel();
      }
    } catch (_) {
      // Réseau momentanément coupé : nouvel essai au prochain tour.
    } finally {
      _checking = false;
    }
  }

  void _stopWaiting() {
    _poll?.cancel();
    setState(() => _pending = null);
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
            return _Message(
              icon: Icons.cloud_off_rounded,
              text: error is ApiException
                  ? error.message
                  : 'Impossible de charger les moyens de paiement. Vérifiez votre connexion.',
              action: OutlinedButton(
                onPressed: () => setState(() => _info = context.read<DeliveryService>().paymentInfo()),
                child: const Text('Réessayer'),
              ),
            );
          }
          final info = snapshot.data!;
          if (info.isEmpty) {
            return const _Message(
              icon: Icons.payments_outlined,
              text: "Le paiement n'est pas encore configuré par l'agence. Contactez S-Delivery.",
            );
          }
          if (_pending != null) return _waiting(_pending!);
          if (!info.online.enabled || _manual) {
            return _ManualPayment(
              delivery: widget.delivery,
              info: info,
              onBack: info.online.enabled ? () => setState(() => _manual = false) : null,
            );
          }
          return _online(info);
        },
      ),
      bottomNavigationBar: FutureBuilder<PaymentInfo>(
        future: _info,
        builder: (context, snapshot) {
          final info = snapshot.data;
          if (info == null || !info.online.enabled || _manual || _pending != null) return const SizedBox.shrink();
          return BottomActionBar(
            children: [
              ElevatedButton(
                onPressed: _starting ? null : _start,
                child: _starting ? const ButtonProgress() : Text('Payer ${formatFcfa(widget.delivery.totalAmount)}'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _online(PaymentInfo info) {
    final methods = info.online.methods;
    final card = methods.any((m) => m.method == _method && m.isCard);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _Amount(amount: widget.delivery.totalAmount, reference: widget.delivery.reference),
        if (info.online.simulation)
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(12)),
            child: const Text(
              'Mode démonstration : aucun argent ne sera débité.',
              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.warning),
            ),
          ),
        if (_failed)
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: const Text(
              "Paiement non abouti : aucun montant n'a été validé. Vous pouvez réessayer.",
              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.error),
            ),
          ),
        const SectionTitle('Moyen de paiement'),
        for (final m in methods)
          _MethodRow(
            method: m.method,
            label: m.label,
            subtitle: m.isCard ? 'Visa, Mastercard · page sécurisée' : 'Validation avec votre code secret',
            selected: _method == m.method,
            onTap: () => setState(() => _method = m.method),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: card ? 'Votre numéro de téléphone' : 'Numéro qui va payer',
            prefixIcon: const Icon(Icons.phone_android_rounded),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Paiement sécurisé. Votre livraison est confirmée automatiquement dès la validation.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        if (info.methods.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          ListRow(
            icon: Icons.receipt_long_outlined,
            title: 'Déjà payé par virement ?',
            subtitle: 'Envoyer la capture de la transaction',
            onTap: () => setState(() => _manual = true),
          ),
        ],
      ],
    );
  }

  Widget _waiting(CheckoutResult pending) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        const Center(child: SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 4))),
        const SizedBox(height: 28),
        Text(
          pending.opensPage ? 'Finalisez le paiement' : 'Validez sur votre téléphone',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          pending.message.isNotEmpty
              ? pending.message
              : 'Nous attendons la confirmation de votre opérateur.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          formatFcfa(widget.delivery.totalAmount),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 28),
        if (pending.opensPage)
          ElevatedButton.icon(
            onPressed: () => _openPage(pending.redirectUrl!),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Rouvrir la page de paiement'),
          ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _check, child: const Text("J'ai validé le paiement")),
        const SizedBox(height: 8),
        TextButton(onPressed: _stopWaiting, child: const Text('Changer de moyen de paiement')),
      ],
    );
  }
}

class _Amount extends StatelessWidget {
  final int amount;
  final String reference;

  const _Amount({required this.amount, required this.reference});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Montant à payer', style: Theme.of(context).textTheme.bodyMedium),
        Text(formatFcfa(amount), style: Theme.of(context).textTheme.displaySmall),
        Text('Livraison $reference', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconSquare(icon, size: 64),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Logo simplifié d'un moyen de paiement.
class _MethodBadge extends StatelessWidget {
  final String method;

  const _MethodBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Widget child) = switch (method) {
      'mixx' => (const Color(0xFFFFD400), AppColors.ink, const Text('M', style: TextStyle(fontWeight: FontWeight.w800))),
      'card' => (AppColors.ink, Colors.white, const Icon(Icons.credit_card_rounded, size: 20, color: Colors.white)),
      _ => (const Color(0xFF0066B3), Colors.white, const Text('F', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
    };
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: DefaultTextStyle.merge(style: TextStyle(color: fg, fontSize: 18), child: child),
    );
  }
}

/// Moyen de paiement sélectionnable (bordure noire quand choisi).
class _MethodRow extends StatelessWidget {
  final String method;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _MethodRow({
    required this.method,
    required this.label,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? AppColors.ink : AppColors.border, width: selected ? 2 : 1),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _MethodBadge(method: method),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                        if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: selected ? AppColors.ink : AppColors.textHint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paiement manuel : virement au numéro marchand puis capture d'écran de la transaction.
class _ManualPayment extends StatefulWidget {
  final Delivery delivery;
  final PaymentInfo info;
  final VoidCallback? onBack;

  const _ManualPayment({required this.delivery, required this.info, this.onBack});

  @override
  State<_ManualPayment> createState() => _ManualPaymentState();
}

class _ManualPaymentState extends State<_ManualPayment> {
  final _formKey = GlobalKey<FormState>();
  final _refController = TextEditingController();
  late final _phoneController = TextEditingController(text: context.read<AuthService>().user?.phoneNumber);
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
    final info = widget.info;
    final selected = info.methods.where((m) => m.method == _method).firstOrNull;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (widget.onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Payer directement dans l\'app'),
              ),
            ),
          _Amount(amount: widget.delivery.totalAmount, reference: widget.delivery.reference),
          const SectionTitle('1. Moyen de paiement'),
          for (final m in info.methods)
            _MethodRow(method: m.method, label: m.label, selected: _method == m.method, onTap: () => setState(() => _method = m.method)),
          if (selected != null) ...[
            const SectionTitle('2. Envoyez le montant à ce numéro'),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(info.merchantName, style: Theme.of(context).textTheme.bodyMedium),
                        Text(selected.merchantNumber,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Copier le numéro',
                    style: IconButton.styleFrom(backgroundColor: AppColors.ink, foregroundColor: Colors.white),
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: selected.merchantNumber));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro copié')));
                    },
                  ),
                ],
              ),
            ),
            if (info.instructions != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(info.instructions!, style: Theme.of(context).textTheme.bodyMedium),
              ),
            const SectionTitle('3. Envoyez la preuve'),
            TextFormField(
              controller: _refController,
              decoration: const InputDecoration(
                labelText: 'Référence / ID de la transaction',
                helperText: 'Indiquée dans le SMS de confirmation',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Référence requise' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numéro ayant effectué le paiement',
                prefixIcon: Icon(Icons.phone_android_rounded),
              ),
              validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 8 ? 'Numéro invalide' : null,
            ),
            const SizedBox(height: 12),
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: _pickScreenshot,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _screenshot == null
                      ? const Column(
                          children: [
                            SizedBox(height: 8),
                            Icon(Icons.add_photo_alternate_outlined, size: 36),
                            SizedBox(height: 6),
                            Text("Ajouter la capture d'écran", style: TextStyle(fontWeight: FontWeight.w700)),
                            SizedBox(height: 8),
                          ],
                        )
                      : Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(File(_screenshot!.path), height: 240, fit: BoxFit.contain),
                            ),
                            const SizedBox(height: 8),
                            const Text('Changer la capture', style: TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _sending ? null : _submit,
              child: _sending ? const ButtonProgress() : const Text('Envoyer la preuve'),
            ),
          ],
        ],
      ),
    );
  }
}
