import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/delivery.dart';
import '../../models/product.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/delivery_service.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/delivery_type_tiles.dart';
import '../../widgets/photos.dart';
import '../../services/geocoding_service.dart';
import '../chat/quick_request_screen.dart';
import '../common/location_picker_screen.dart';

/// Formulaire de demande de livraison du point A (récupération) au point B (destination).
/// Avec [product], le point A est l'adresse du vendeur fixée par l'admin.
class NewDeliveryScreen extends StatefulWidget {
  final DeliveryType initialType;
  final Product? product;
  final int quantity;

  const NewDeliveryScreen({super.key, this.initialType = DeliveryType.colis, this.product, this.quantity = 1});

  @override
  State<NewDeliveryScreen> createState() => _NewDeliveryScreenState();
}

class _NewDeliveryScreenState extends State<NewDeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickupAddress = TextEditingController();
  final _pickupName = TextEditingController();
  final _pickupPhone = TextEditingController();
  final _dropoffAddress = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();

  late DeliveryType _type =
      widget.product != null && widget.initialType == DeliveryType.programmee ? DeliveryType.colis : widget.initialType;
  LatLng? _pickup;
  LatLng? _dropoff;
  DateTime? _scheduledAt;
  DateTime? _deadline;
  DeliveryQuote? _quote;
  bool _quoting = false;
  bool _submitting = false;

  /// Photos des articles à livrer (aident le livreur à reconnaître le colis).
  final _photos = <String>[];
  static const _maxPhotos = 6;

  bool get _isOrder => widget.product != null;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthService>().user;
    if (!_isOrder && user != null) {
      _pickupName.text = user.name;
      _pickupPhone.text = user.phoneNumber;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _pickupAddress,
      _pickupName,
      _pickupPhone,
      _dropoffAddress,
      _recipientName,
      _recipientPhone,
      _description,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick({required bool pickup}) async {
    final result = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          title: pickup ? 'Point A · Récupération' : 'Point B · Destination',
          initial: pickup ? _pickup : (_dropoff ?? _pickup),
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (pickup) {
        _pickup = result.point;
        _pickupAddress.text = result.label;
      } else {
        _dropoff = result.point;
        _dropoffAddress.text = result.label;
      }
    });
    _refreshQuote();
  }

  /// Heure limite à laquelle la livraison doit être faite (au moins 30 min plus tard).
  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final initial = _deadline ?? now.add(const Duration(hours: 2));
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
      initialDate: initial,
      helpText: 'Livrer au plus tard le',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Avant quelle heure ?',
    );
    if (time == null || !mounted) return;
    final chosen = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (chosen.isBefore(now.add(const Duration(minutes: 30)))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Choisissez une heure au moins 30 minutes plus tard."),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _deadline = chosen);
  }

  Future<void> _refreshQuote() async {
    // Pour une commande, le devis exact est calculé par le serveur à la création (adresse vendeur).
    if (_isOrder || _pickup == null || _dropoff == null) return;
    setState(() => _quoting = true);
    try {
      final quote = await context.read<DeliveryService>().quote(
            type: _type,
            pickupLat: _pickup!.latitude,
            pickupLng: _pickup!.longitude,
            dropoffLat: _dropoff!.latitude,
            dropoffLng: _dropoff!.longitude,
          );
      if (mounted) setState(() => _quote = quote);
    } on ApiException {
      if (mounted) setState(() => _quote = null);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: _scheduledAt ?? now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() => _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  /// Programmation par photo : réservée aux clients habitués (au moins une livraison effectuée).
  Future<void> _openPhotoProgramming() async {
    final regular = context.read<AuthService>().user?.isRegular ?? false;
    if (!regular) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.lock_clock, color: AppColors.primaryDark, size: 36),
          title: const Text('Programmation par photo'),
          content: const Text(
            "Disponible après votre première livraison. En attendant, remplissez le formulaire ci-dessous : "
            'vous pouvez aussi y joindre les photos de vos articles.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Compris'))],
        ),
      );
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const QuickRequestScreen()));
  }

  Future<void> _addPhotos() async {
    final remaining = _maxPhotos - _photos.length;
    final fromCamera = await showModalBottomSheet<bool>(
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
    if (fromCamera == null) return;

    final List<String> picked;
    if (fromCamera) {
      final path = await pickPhotoFromCamera();
      picked = path == null ? const [] : [path];
    } else {
      picked = await pickPhotosFromGallery(limit: remaining);
    }
    if (mounted && picked.isNotEmpty) setState(() => _photos.addAll(picked.take(remaining)));
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    void error(String msg) => messenger.showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.error));

    if (!_formKey.currentState!.validate()) return;
    if (!_isOrder && _pickup == null) return error('Placez le point A (récupération) sur la carte.');
    if (_dropoff == null) return error('Placez le point B (destination) sur la carte.');
    if (_type == DeliveryType.programmee && _scheduledAt == null) {
      return error("Choisissez la date et l'heure de la livraison programmée.");
    }

    String? orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

    final payload = <String, dynamic>{
      'type': _type.value,
      if (_isOrder) ...{
        'product_id': widget.product!.id,
        'quantity': widget.quantity,
      } else ...{
        'pickup_address': _pickupAddress.text.trim(),
        'pickup_lat': _pickup!.latitude,
        'pickup_lng': _pickup!.longitude,
        'pickup_contact_name': orNull(_pickupName),
        'pickup_contact_phone': orNull(_pickupPhone),
      },
      'dropoff_address': _dropoffAddress.text.trim(),
      'dropoff_lat': _dropoff!.latitude,
      'dropoff_lng': _dropoff!.longitude,
      'recipient_name': _recipientName.text.trim(),
      'recipient_phone': _recipientPhone.text.trim(),
      'package_description': orNull(_description),
      'notes': orNull(_notes),
      if (_scheduledAt != null) 'scheduled_at': _scheduledAt!.toUtc().toIso8601String(),
      if (_deadline != null) 'deadline_at': _deadline!.toUtc().toIso8601String(),
    };

    setState(() => _submitting = true);
    try {
      final service = context.read<DeliveryService>();
      final delivery = await service.createDelivery(payload);

      // Photos envoyées une à une : un échec n'annule pas la demande déjà créée.
      var failed = 0;
      for (final path in _photos) {
        try {
          await service.addDeliveryPhoto(delivery.id, path);
        } on ApiException {
          failed++;
        }
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(failed == 0
            ? 'Demande créée. Effectuez le paiement pour la confirmer.'
            : 'Demande créée, mais $failed photo(s) non envoyée(s).'),
        backgroundColor: failed == 0 ? AppColors.success : AppColors.warning,
      ));
      Navigator.of(context).pop(delivery);
    } on ApiException catch (e) {
      error(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final types = DeliveryType.values.where((t) => !_isOrder || t != DeliveryType.programmee);

    return Scaffold(
      appBar: AppBar(title: Text(_isOrder ? 'Commander' : 'Nouvelle livraison')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (product != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.shopping_bag, color: AppColors.primaryDark),
                  title: Text('${widget.quantity} × ${product.name}'),
                  subtitle: Text('Retrait : ${product.vendorName ?? product.pickupAddress}'),
                  trailing: Text(formatFcfa(product.price * widget.quantity),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            const SizedBox(height: 8),
            Text('Type de livraison', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DeliveryTypeTiles(
              types: types.toList(),
              selected: _type,
              onTap: (t) {
                setState(() => _type = t);
                _refreshQuote();
              },
            ),
            if (_type == DeliveryType.programmee) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickSchedule,
                icon: const Icon(Icons.event),
                label: Text(_scheduledAt == null ? 'Choisir date et heure' : formatDateTime(_scheduledAt!)),
              ),
            ],
            // Sous les programmations : commande par simple photo du colis (l'agence complète le reste).
            if (!_isOrder) ...[
              const SizedBox(height: 12),
              _PhotoProgrammingTile(onTap: _openPhotoProgramming),
            ],
            const SizedBox(height: 12),
            // Heure limite de livraison (visible par le livreur, avec rappels si elle approche).
            Material(
              color: _deadline == null ? AppColors.surface : AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                onTap: _pickDeadline,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: const Icon(Icons.alarm, color: AppColors.secondary),
                title: Text(
                  _deadline == null ? 'Heure limite de livraison' : 'À livrer avant ${formatDateTime(_deadline!)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(_deadline == null
                    ? 'Facultatif · le livreur sera alerté si elle approche'
                    : 'Touchez pour modifier'),
                trailing: _deadline == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        tooltip: "Retirer l'heure limite",
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _deadline = null),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            if (!_isOrder) ...[
              const _SectionTitle(letter: 'A', color: AppColors.success, title: 'Récupération du colis'),
              _MapButton(point: _pickup, onTap: () => _pick(pickup: true)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pickupAddress,
                decoration: const InputDecoration(
                  labelText: 'Adresse / repère (quartier, rue, bâtiment)',
                  prefixIcon: Icon(Icons.my_location),
                ),
                validator: _required("Indiquez l'adresse de récupération"),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pickupName,
                      decoration: const InputDecoration(labelText: 'Contact sur place'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _pickupPhone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Téléphone'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            const _SectionTitle(letter: 'B', color: AppColors.error, title: 'Destination de livraison'),
            _MapButton(point: _dropoff, onTap: () => _pick(pickup: false)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dropoffAddress,
              decoration: const InputDecoration(
                labelText: 'Adresse / repère de livraison',
                prefixIcon: Icon(Icons.location_on),
              ),
              validator: _required("Indiquez l'adresse de livraison"),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _recipientName,
                    decoration: const InputDecoration(labelText: 'Destinataire'),
                    validator: _required('Nom requis'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _recipientPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Téléphone'),
                    validator: _required('Téléphone requis'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (!_isOrder)
              TextFormField(
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description du colis / pli',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.photo_library_outlined, size: 20),
                const SizedBox(width: 8),
                Text('Photos des articles', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${_photos.length}/$_maxPhotos · facultatif', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            LocalPhotoGrid(
              paths: _photos,
              max: _maxPhotos,
              onAdd: _addPhotos,
              onRemove: (i) => setState(() => _photos.removeAt(i)),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Instructions pour le livreur (facultatif)',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      // Prix et bouton toujours visibles, au-dessus de la barre de navigation du téléphone.
      bottomNavigationBar: BottomActionBar(
        summary: _isOrder
            ? Text(
                'Frais de livraison calculés selon la distance et ajoutés au total.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            : _QuoteSummary(quote: _quote, loading: _quoting),
        children: [
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting ? const ButtonProgress() : Text(_isOrder ? 'Valider la commande' : 'Créer la demande'),
          ),
        ],
      ),
    );
  }

  static FormFieldValidator<String> _required(String message) =>
      (v) => (v == null || v.trim().isEmpty) ? message : null;
}

/// Tuile pleine largeur « Programmation par photo », sous les types de livraison.
class _PhotoProgrammingTile extends StatelessWidget {
  final VoidCallback onTap;

  const _PhotoProgrammingTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.secondary,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary,
                child: Icon(Icons.add_a_photo, color: AppColors.onPrimary, size: 20),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Programmation par photo',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                    Text('Une simple photo du colis suffit',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String letter;
  final Color color;
  final String title;

  const _SectionTitle({required this.letter, required this.color, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: color,
            child: Text(letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final LatLng? point;
  final VoidCallback onTap;

  const _MapButton({required this.point, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final picked = point != null;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(picked ? Icons.check_circle : Icons.map_outlined, color: picked ? AppColors.success : null),
      label: Text(
        picked
            ? 'Position choisie (${point!.latitude.toStringAsFixed(5)}, ${point!.longitude.toStringAsFixed(5)})'
            : 'Choisir sur la carte',
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Prix estimé affiché dans la barre fixe du bas.
class _QuoteSummary extends StatelessWidget {
  final DeliveryQuote? quote;
  final bool loading;

  const _QuoteSummary({required this.quote, required this.loading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          if (loading)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else if (quote == null)
            Expanded(
              child: Text(
                'Placez A et B sur la carte pour voir le prix.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else ...[
            Expanded(
              child:
                  Text('Prix estimé · ${formatKm(quote!.distanceKm)}', style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(formatFcfa(quote!.deliveryFee), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }
}
