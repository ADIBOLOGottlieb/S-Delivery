import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/delivery.dart';
import '../../models/product.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/delivery_service.dart';
import '../../services/geocoding_service.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/delivery_map.dart';
import '../../widgets/photos.dart';
import '../chat/chat_screen.dart';
import '../chat/quick_request_screen.dart';
import '../common/location_picker_screen.dart';

/// Taille du colis (comme le module colis de Gozem) : remplace le choix du type de livraison.
enum ParcelSize {
  small('Petit', 'Enveloppe, documents', Icons.mail_outline_rounded),
  medium('Moyen', 'Sac, boîte', Icons.shopping_bag_outlined),
  large('Grand', 'Carton, gros colis', Icons.inventory_2_outlined);

  const ParcelSize(this.label, this.hint, this.icon);
  final String label;
  final String hint;
  final IconData icon;
}

/// Envoi d'un colis du point A (récupération) au point B (destination), façon Gozem :
/// carte en haut, trajet « D'où → Où », J'envoie / Je reçois, taille, Maintenant / Programmer,
/// prix et bouton « Commander » toujours visibles en bas.
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
  static const _lome = LatLng(6.1319, 1.2228);

  final _formKey = GlobalKey<FormState>();
  final _pickupAddress = TextEditingController();
  final _pickupName = TextEditingController();
  final _pickupPhone = TextEditingController();
  final _dropoffAddress = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();

  /// true : j'envoie (je suis au point A) ; false : je reçois (je suis au point B).
  bool _sending = true;
  late ParcelSize _size = widget.initialType == DeliveryType.plis ? ParcelSize.small : ParcelSize.medium;
  late bool _later = widget.product == null && widget.initialType == DeliveryType.programmee;
  LatLng? _pickup;
  LatLng? _dropoff;
  DateTime? _scheduledAt;
  DateTime? _deadline;
  DeliveryQuote? _quote;
  bool _quoting = false;
  bool _quoteFailed = false;
  int _quoteSeq = 0;
  bool _submitting = false;

  /// Position actuelle du client, posée d'office de son côté (départ s'il envoie, arrivée s'il reçoit).
  Place? _here;

  /// Photos des articles à livrer (aident le livreur à reconnaître le colis).
  final _photos = <String>[];
  static const _maxPhotos = 6;

  bool get _isOrder => widget.product != null;

  /// Type envoyé au serveur : déduit de la taille et du moment choisis.
  DeliveryType get _type => _later
      ? DeliveryType.programmee
      : (_size == ParcelSize.small && !_isOrder ? DeliveryType.plis : DeliveryType.colis);

  @override
  void initState() {
    super.initState();
    _applyRole();
    if (!_isOrder) _locateMe();
  }

  /// Comme Gozem : le point de l'utilisateur est rempli avec sa position, sans rien taper.
  Future<void> _locateMe() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      final point = LatLng(pos.latitude, pos.longitude);
      final place = await GeocodingService().reverse(point) ?? Place(point: point, label: 'Ma position');
      if (!mounted) return;
      setState(() {
        _here = place;
        _placeMine();
      });
      _refreshQuote();
    } catch (_) {
      // Sans position, le client choisit le point sur la carte.
    }
  }

  /// Pose ma position de mon côté (si ce point est encore vide) et la retire de l'autre côté.
  void _placeMine() {
    final here = _here;
    if (here == null || _isOrder) return;
    if (_sending) {
      if (_dropoff == here.point) {
        _dropoff = null;
        _dropoffAddress.clear();
      }
      if (_pickup == null) {
        _pickup = here.point;
        _pickupAddress.text = here.label;
      }
    } else {
      if (_pickup == here.point) {
        _pickup = null;
        _pickupAddress.clear();
      }
      if (_dropoff == null) {
        _dropoff = here.point;
        _dropoffAddress.text = here.label;
      }
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

  /// Mes coordonnées vont du côté où je me trouve (expéditeur ou destinataire).
  void _applyRole() {
    final user = context.read<AuthService>().user;
    if (user == null) return;
    // Commande au marché : c'est moi qui reçois.
    if (_isOrder) {
      _recipientName.text = user.name;
      _recipientPhone.text = user.phoneNumber;
      return;
    }
    final mine = _sending ? (_pickupName, _pickupPhone) : (_recipientName, _recipientPhone);
    final theirs = _sending ? (_recipientName, _recipientPhone) : (_pickupName, _pickupPhone);
    mine.$1.text = user.name;
    mine.$2.text = user.phoneNumber;
    if (theirs.$2.text == user.phoneNumber) {
      theirs.$1.clear();
      theirs.$2.clear();
    }
  }

  Future<void> _pick({required bool pickup}) async {
    final result = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          title: pickup ? 'Où récupérer le colis ?' : 'Où livrer le colis ?',
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

  /// Précise le repère (bâtiment, couleur du portail…) après le choix sur la carte.
  Future<void> _editLandmark({required bool pickup}) async {
    final controller = TextEditingController(text: (pickup ? _pickupAddress : _dropoffAddress).text);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(pickup ? 'Repère de récupération' : 'Repère de livraison'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'Quartier, rue, bâtiment, couleur du portail…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    setState(() => (pickup ? _pickupAddress : _dropoffAddress).text = value);
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
        content: Text('Choisissez une heure au moins 30 minutes plus tard.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _deadline = chosen);
  }

  Future<void> _refreshQuote() async {
    // Pour une commande, le devis exact est calculé par le serveur à la création (adresse vendeur).
    if (_isOrder || _pickup == null || _dropoff == null) return;
    // Seule la dernière demande de prix compte (changements rapides de taille ou de moment).
    final seq = ++_quoteSeq;
    setState(() {
      _quoting = true;
      _quoteFailed = false;
    });
    try {
      final quote = await context.read<DeliveryService>().quote(
            type: _type,
            pickupLat: _pickup!.latitude,
            pickupLng: _pickup!.longitude,
            dropoffLat: _dropoff!.latitude,
            dropoffLng: _dropoff!.longitude,
          );
      if (mounted && seq == _quoteSeq) setState(() => _quote = quote);
    } on ApiException {
      if (mounted && seq == _quoteSeq) {
        setState(() {
          _quote = null;
          _quoteFailed = true;
        });
      }
    } finally {
      if (mounted && seq == _quoteSeq) setState(() => _quoting = false);
    }
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: _scheduledAt ?? now,
      helpText: 'Jour de passage',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? now.add(const Duration(hours: 1))),
      helpText: 'Heure de passage',
    );
    if (time == null || !mounted) return;
    final chosen = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (chosen.isBefore(DateTime.now().add(const Duration(minutes: 10)))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Choisissez une heure de passage au moins 10 minutes plus tard.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() {
      _later = true;
      _scheduledAt = chosen;
    });
  }

  /// Saisies faites par le client (hors position et coordonnées remplies d'office), perdues en quittant le formulaire.
  bool get _hasTypedData {
    final user = context.read<AuthService>().user;
    final here = _here?.point;
    bool typed(TextEditingController c, [String? prefilled]) {
      final text = c.text.trim();
      return text.isNotEmpty && text != prefilled;
    }

    return (_pickup != null && _pickup != here) ||
        (_dropoff != null && _dropoff != here) ||
        typed(_pickupName, user?.name) ||
        typed(_pickupPhone, user?.phoneNumber) ||
        typed(_recipientName, user?.name) ||
        typed(_recipientPhone, user?.phoneNumber) ||
        typed(_description) ||
        typed(_notes);
  }

  /// Programmation par photo : ouverte à tout client connecté, au même titre que le formulaire.
  /// Les photos déjà jointes au formulaire sont reprises ; les autres saisies sont perdues (confirmation).
  Future<void> _openPhotoProgramming() async {
    if (_hasTypedData) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Passer à la programmation par photo ?'),
          content: const Text('Vos informations saisies seront perdues, seules les photos sont gardées.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Rester ici')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuer')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => QuickRequestScreen(initialPhotos: List.of(_photos))),
    );
  }

  /// Adresse inconnue mais photos jointes : on les envoie à l'agence, qui complète avec le client
  /// dans la discussion (même circuit que la programmation par photo).
  Future<void> _sendToAgency() async {
    String? orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final contact = [orNull(_recipientName), orNull(_recipientPhone)].whereType<String>().join(' · ');
    final message = [
      if (_pickup != null) 'Récupération : ${_pickupAddress.text.trim()}',
      if (_dropoff != null) 'Livraison : ${_dropoffAddress.text.trim()}',
      if (contact.isNotEmpty) 'Destinataire : $contact',
      'Taille : ${_size.label}',
      if (orNull(_description) != null) 'Contenu : ${orNull(_description)}',
      if (orNull(_notes) != null) 'Instructions : ${orNull(_notes)}',
    ].join('\n');

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _submitting = true);
    try {
      final request = await context.read<DeliveryService>().createChatRequest(photoPaths: _photos, message: message);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChatScreen(requestId: request.id, initial: request)),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Adresse manquante : avec des photos, propose l'envoi à l'agence au lieu de bloquer.
  Future<void> _missingAddress(String what) async {
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Indiquez $what. Vous ne la connaissez pas ? Utilisez « Programmation par photo ».'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.add_a_photo, color: AppColors.primaryDark, size: 36),
        title: const Text('Adresse manquante'),
        content: Text(
          'Pour un prix immédiat, indiquez $what.\n\n'
          "Sinon, envoyez vos photos à l'agence : elle vous contacte et complète l'adresse avec vous.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Compléter l'adresse")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Envoyer à l'agence")),
        ],
      ),
    );
    if (send == true && mounted) await _sendToAgency();
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
      final path = await pickPhotoFromCamera(keep: _photos);
      picked = path == null ? const [] : [path];
    } else {
      picked = await pickPhotosFromGallery(limit: remaining);
    }
    if (mounted && picked.isNotEmpty) setState(() => _photos.addAll(picked.take(remaining)));
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    void error(String msg) => messenger.showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.error));

    if (!_isOrder && _pickup == null) return _missingAddress('où récupérer le colis');
    if (_dropoff == null) return _missingAddress('où livrer le colis');
    if (!_formKey.currentState!.validate()) return;
    if (_later && _scheduledAt == null) return error("Choisissez le jour et l'heure de passage.");
    final now = DateTime.now();
    if (_later && _scheduledAt!.isBefore(now.add(const Duration(minutes: 5)))) {
      return error("L'heure de passage est dépassée : choisissez-en une nouvelle.");
    }
    if (_deadline != null && _deadline!.isBefore(now.add(const Duration(minutes: 30)))) {
      return error("L'heure limite est trop proche : choisissez-la au moins 30 minutes plus tard.");
    }
    if (_later && _deadline != null && !_deadline!.isAfter(_scheduledAt!)) {
      return error("L'heure limite doit être après l'heure de passage.");
    }

    String? orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final details = orNull(_description);
    final description = [
      if (!_isOrder) 'Taille : ${_size.label} (${_size.hint.toLowerCase()})',
      if (details != null) details,
    ].join(' · ');

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
      'package_description': description.isEmpty ? null : description,
      'notes': orNull(_notes),
      if (_later && _scheduledAt != null) 'scheduled_at': _scheduledAt!.toUtc().toIso8601String(),
      if (_deadline != null) 'deadline_at': _deadline!.toUtc().toIso8601String(),
    };

    setState(() => _submitting = true);
    final service = context.read<DeliveryService>();
    final Delivery delivery;
    try {
      delivery = await service.createDelivery(payload);
    } on ApiException catch (e) {
      error(e.message);
      if (mounted) setState(() => _submitting = false);
      return;
    } catch (_) {
      error('Une erreur est survenue. Vérifiez dans Suivi avant de recommencer.');
      if (mounted) setState(() => _submitting = false);
      return;
    }

    // Livraison créée : l'écran se ferme avec elle quoi qu'il arrive aux photos (pas de double commande).
    var failed = 0;
    for (final path in _photos) {
      try {
        await service.addDeliveryPhoto(delivery.id, path);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(failed == 0
          ? 'Demande créée. Effectuez le paiement pour la confirmer.'
          : 'Demande créée. $failed photo(s) non envoyée(s), ajoutez-les depuis le suivi.'),
      backgroundColor: failed == 0 ? AppColors.success : AppColors.warning,
    ));
    Navigator.of(context).pop(delivery);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final textTheme = Theme.of(context).textTheme;
    final otherSide = _sending || _isOrder;

    // Pas de retour pendant l'envoi (demande et photos) : la commande partirait sans suite.
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: AppBar(title: Text(_isOrder ? 'Commander' : 'Envoyer un colis')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              _RouteMap(pickup: _pickup, dropoff: _dropoff, fallback: _lome),
              // Carte du trajet qui chevauche la carte, comme une feuille Gozem.
              Transform.translate(
                offset: const Offset(0, -28),
                child: _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (product != null) ...[
                        _OrderSummary(product: product, quantity: widget.quantity),
                        const SizedBox(height: 14),
                      ] else ...[
                        _RoleSwitch(
                          sending: _sending,
                          onChanged: (v) {
                            setState(() {
                              _sending = v;
                              _applyRole();
                              _placeMine();
                            });
                            _refreshQuote();
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      _RouteStop(
                        color: AppColors.success,
                        square: false,
                        label: 'Récupération',
                        value: product != null
                            ? (product.vendorName ?? product.pickupAddress)
                            : (_pickup == null ? null : _pickupAddress.text),
                        placeholder: 'Où récupérer le colis ?',
                        onTap: product != null ? null : () => _pick(pickup: true),
                        onEdit: product != null || _pickup == null ? null : () => _editLandmark(pickup: true),
                      ),
                      const _RouteConnector(),
                      _RouteStop(
                        color: AppColors.error,
                        square: true,
                        label: 'Destination',
                        value: _dropoff == null ? null : _dropoffAddress.text,
                        placeholder: 'Où livrer le colis ?',
                        onTap: () => _pick(pickup: false),
                        onEdit: _dropoff == null ? null : () => _editLandmark(pickup: false),
                      ),
                    ],
                  ),
                ),
              ),
              // Personne à l'autre bout (l'utilisateur est pré-rempli de son côté).
              _SectionLabel(otherSide ? 'Qui reçoit le colis ?' : 'Qui remet le colis ?'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('name-$otherSide'),
                      controller: otherSide ? _recipientName : _pickupName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nom', prefixIcon: Icon(Icons.person_outline)),
                      validator: _required('Nom requis'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('phone-$otherSide'),
                      controller: otherSide ? _recipientPhone : _pickupPhone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Numéro', prefixIcon: Icon(Icons.phone_outlined)),
                      validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 8 ? 'Numéro invalide' : null,
                    ),
                  ),
                ],
              ),
              if (!_isOrder) ...[
                const _SectionLabel('Taille du colis'),
                Row(
                  children: [
                    for (final s in ParcelSize.values) ...[
                      if (s != ParcelSize.values.first) const SizedBox(width: 10),
                      Expanded(
                        child: _ChoiceTile(
                          icon: s.icon,
                          title: s.label,
                          subtitle: s.hint,
                          selected: _size == s,
                          onTap: () {
                            setState(() => _size = s);
                            _refreshQuote();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const _SectionLabel('Quand ?'),
                Row(
                  children: [
                    Expanded(
                      child: _ChoiceTile(
                        icon: Icons.bolt_rounded,
                        title: 'Maintenant',
                        subtitle: 'Dès que possible',
                        selected: !_later,
                        onTap: () {
                          setState(() => _later = false);
                          _refreshQuote();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ChoiceTile(
                        icon: Icons.event_rounded,
                        title: 'Programmer',
                        subtitle: _later && _scheduledAt != null ? formatDateTime(_scheduledAt!) : 'Jour et heure',
                        selected: _later,
                        onTap: () async {
                          await _pickSchedule();
                          _refreshQuote();
                        },
                      ),
                    ),
                  ],
                ),
                // Sous les programmations : commande par simple photo du colis (l'agence complète le reste).
                const SizedBox(height: 12),
                _PhotoProgrammingTile(onTap: _openPhotoProgramming),
              ],
              const _SectionLabel('Options'),
              _OptionTile(
                icon: Icons.alarm,
                title: _deadline == null ? 'Heure limite de livraison' : 'À livrer avant ${formatDateTime(_deadline!)}',
                subtitle:
                    _deadline == null ? 'Facultatif · le livreur est alerté si elle approche' : 'Touchez pour modifier',
                highlighted: _deadline != null,
                onTap: _pickDeadline,
                onClear: _deadline == null ? null : () => setState(() => _deadline = null),
              ),
              const SizedBox(height: 12),
              if (!_isOrder) ...[
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Que contient le colis ? (facultatif)',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Instructions pour le livreur (facultatif)',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.photo_library_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('Photos des articles', style: textTheme.titleMedium),
                  const Spacer(),
                  Text('${_photos.length}/$_maxPhotos · facultatif', style: textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 10),
              LocalPhotoGrid(
                paths: _photos,
                max: _maxPhotos,
                onAdd: _addPhotos,
                onRemove: (i) => setState(() => _photos.removeAt(i)),
              ),
            ],
          ),
        ),
        // Prix et bouton toujours visibles, au-dessus de la barre de navigation du téléphone.
        bottomNavigationBar: BottomActionBar(
          summary: _isOrder
              ? Text('Frais de livraison calculés selon la distance et ajoutés au total.', style: textTheme.bodySmall)
              : _QuoteSummary(quote: _quote, loading: _quoting, failed: _quoteFailed, onRetry: _refreshQuote),
          children: [
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting ? const ButtonProgress() : Text(_isOrder ? 'Valider la commande' : 'Commander · payer ensuite'),
            ),
          ],
        ),
      ),
    );
  }

  static FormFieldValidator<String> _required(String message) =>
      (v) => (v == null || v.trim().isEmpty) ? message : null;
}

/// Carte d'en-tête : trajet A → B dès que les deux points sont connus, sinon Lomé.
class _RouteMap extends StatelessWidget {
  final LatLng? pickup;
  final LatLng? dropoff;
  final LatLng fallback;

  const _RouteMap({required this.pickup, required this.dropoff, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final points = <LatLng>[if (pickup != null) pickup!, if (dropoff != null) dropoff!];
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 210,
        child: FlutterMap(
          key: ValueKey(points.map((p) => '${p.latitude},${p.longitude}').join('|')),
          options: MapOptions(
            initialCenter: points.isEmpty ? fallback : points.first,
            initialZoom: points.isEmpty ? 12.5 : 15,
            initialCameraFit: points.length == 2
                ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.fromLTRB(40, 30, 40, 60))
                : null,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            osmTiles(),
            if (points.length == 2)
              PolylineLayer(polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 4,
                  color: AppColors.secondary.withValues(alpha: 0.75),
                  pattern: StrokePattern.dashed(segments: const [12, 8]),
                ),
              ]),
            MarkerLayer(markers: [
              if (pickup != null) pointMarker(pickup!, 'A', AppColors.success),
              if (dropoff != null) pointMarker(dropoff!, 'B', AppColors.error),
            ]),
            osmAttribution(),
          ],
        ),
      ),
    );
  }
}

/// Panneau ivoire arrondi avec ombre douce.
class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.22), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}

/// Bascule « J'envoie / Je reçois ».
class _RoleSwitch extends StatelessWidget {
  final bool sending;
  final ValueChanged<bool> onChanged;

  const _RoleSwitch({required this.sending, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget option(bool value, IconData icon, String label) {
      final active = sending == value;
      return Expanded(
        child: Semantics(
          selected: active,
          button: true,
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: active ? AppColors.onPrimary : Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(fontWeight: FontWeight.w700, color: active ? AppColors.onPrimary : Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.secondary, borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          option(true, Icons.north_east_rounded, "J'envoie"),
          option(false, Icons.south_west_rounded, 'Je reçois'),
        ],
      ),
    );
  }
}

/// Étape du trajet : pastille (ronde = départ, carrée = arrivée), libellé et adresse.
class _RouteStop extends StatelessWidget {
  final Color color;
  final bool square;
  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  const _RouteStop({
    required this.color,
    required this.square,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final empty = value == null || value!.isEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: square ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: square ? BorderRadius.circular(4) : null,
                border: Border.all(color: AppColors.card, width: 3),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    empty ? placeholder : value!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: empty ? FontWeight.w500 : FontWeight.w700,
                      color: empty ? AppColors.textHint : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (onEdit != null)
              IconButton(
                  tooltip: 'Préciser le repère', onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 20))
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Pointillés verticaux entre départ et arrivée.
class _RouteConnector extends StatelessWidget {
  const _RouteConnector();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
                width: 2, height: 4, margin: const EdgeInsets.symmetric(vertical: 1.5), color: AppColors.textHint),
        ],
      ),
    );
  }
}

/// Produit commandé (mode marketplace).
class _OrderSummary extends StatelessWidget {
  final Product product;
  final int quantity;

  const _OrderSummary({required this.product, required this.quantity});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          backgroundColor: AppColors.primary,
          child: Icon(Icons.shopping_basket, color: AppColors.onPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('$quantity × ${product.name}',
              style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        Text(formatFcfa(product.price * quantity), style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// Choix en carte (taille, moment) : jaune et contour noir quand sélectionné.
class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primary : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? AppColors.secondary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              children: [
                Icon(icon, size: 26, color: AppColors.secondary),
                const SizedBox(height: 6),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(fontSize: 11.5, color: selected ? AppColors.onPrimary : AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Option facultative en ligne (heure limite…).
class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.highlighted,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? AppColors.primarySoft : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(icon, color: AppColors.secondary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: onClear == null
            ? const Icon(Icons.chevron_right)
            : IconButton(tooltip: 'Retirer', icon: const Icon(Icons.close), onPressed: onClear),
      ),
    );
  }
}

/// Tuile pleine largeur « Programmation par photo », sous les programmations.
class _PhotoProgrammingTile extends StatelessWidget {
  final VoidCallback onTap;

  const _PhotoProgrammingTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.secondary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
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
                    Text('Une simple photo du colis suffit', style: TextStyle(color: Colors.white70, fontSize: 12)),
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

/// Prix estimé affiché dans la barre fixe du bas.
class _QuoteSummary extends StatelessWidget {
  final DeliveryQuote? quote;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  const _QuoteSummary({required this.quote, required this.loading, required this.failed, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          if (loading)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else if (failed)
            Expanded(
              child: InkWell(
                onTap: onRetry,
                child: Row(
                  children: [
                    const Icon(Icons.refresh_rounded, size: 20, color: AppColors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Prix indisponible · toucher pour réessayer',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            )
          else if (quote == null)
            Expanded(
              child: Text('Indiquez départ et destination pour le prix.',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
            )
          else ...[
            const Icon(Icons.route_rounded, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(child: Text(formatKm(quote!.distanceKm), style: Theme.of(context).textTheme.bodyMedium)),
            Text(formatFcfa(quote!.deliveryFee), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}
