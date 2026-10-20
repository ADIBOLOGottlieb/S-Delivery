import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/delivery.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/delivery_service.dart';
import '../../services/geocoding_service.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/delivery_map.dart';
import '../../widgets/photos.dart';
import '../../widgets/ui.dart';
import '../chat/chat_screen.dart';
import '../chat/quick_request_screen.dart';
import '../common/location_picker_screen.dart';

/// Taille du colis : remplace le choix du type de livraison.
enum ParcelSize {
  small('Pli', 'Enveloppe, documents, clés', Icons.mail_outline_rounded),
  medium('Colis', 'Sac, boîte, vêtements', Icons.shopping_bag_outlined),
  large('Gros colis', 'Carton, plusieurs articles', Icons.inventory_2_outlined);

  const ParcelSize(this.label, this.hint, this.icon);
  final String label;
  final String hint;
  final IconData icon;
}

/// Nouvelle livraison du point A (récupération) au point B (destination), façon apps de mobilité :
/// carte en haut, trajet « Départ → Arrivée », J'envoie / Je reçois, taille, Maintenant / Programmer,
/// prix et bouton « Commander » toujours visibles en bas.
class NewDeliveryScreen extends StatefulWidget {
  final DeliveryType initialType;

  /// Le client reçoit le colis (il est au point B).
  final bool receiving;

  /// Destination déjà connue (adresse récente).
  final DeliveryPoint? initialDropoff;

  const NewDeliveryScreen({
    super.key,
    this.initialType = DeliveryType.colis,
    this.receiving = false,
    this.initialDropoff,
  });

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
  late bool _sending = !widget.receiving;
  late ParcelSize _size = widget.initialType == DeliveryType.plis ? ParcelSize.small : ParcelSize.medium;
  late bool _later = widget.initialType == DeliveryType.programmee;
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

  /// Type envoyé au serveur : déduit de la taille et du moment choisis.
  DeliveryType get _type =>
      _later ? DeliveryType.programmee : (_size == ParcelSize.small ? DeliveryType.plis : DeliveryType.colis);

  @override
  void initState() {
    super.initState();
    final known = widget.initialDropoff;
    if (known != null) {
      _dropoff = known.latLng;
      _dropoffAddress.text = known.address;
      _recipientName.text = known.contactName ?? '';
      _recipientPhone.text = known.contactPhone ?? '';
    }
    _applyRole();
    _locateMe();
    // Programmée depuis l'accueil : le choix du jour et de l'heure s'ouvre tout de suite.
    if (_later) WidgetsBinding.instance.addPostFrameCallback((_) => _pickSchedule());
  }

  /// Le point de l'utilisateur est rempli avec sa position, sans rien taper.
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
    if (here == null) return;
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
    final mine = _sending ? (_pickupName, _pickupPhone) : (_recipientName, _recipientPhone);
    final theirs = _sending ? (_recipientName, _recipientPhone) : (_pickupName, _pickupPhone);
    mine.$1.text = user.name;
    mine.$2.text = user.phoneNumber;
    if (theirs.$2.text == user.phoneNumber) {
      theirs.$1.clear();
      theirs.$2.clear();
    }
  }

  void _switchRole(bool sending) {
    if (sending == _sending) return;
    setState(() {
      _sending = sending;
      _applyRole();
      _placeMine();
    });
    _refreshQuote();
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
    if (_pickup == null || _dropoff == null) return;
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
    _refreshQuote();
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

  /// Programmation par photo : les photos déjà jointes sont reprises, les autres saisies sont perdues (confirmation).
  Future<void> _openPhotoProgramming() async {
    if (_hasTypedData) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Passer à la commande par photo ?'),
          content: const Text('Vos informations saisies seront perdues, seules les photos sont gardées.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Rester ici')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuer')),
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
        content: Text('Indiquez $what. Vous ne la connaissez pas ? Utilisez « Commander par photo ».'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.add_a_photo_outlined, size: 32),
        title: const Text('Adresse manquante'),
        content: Text(
          'Pour un prix immédiat, indiquez $what.\n\n'
          "Sinon, envoyez vos photos à l'agence : elle vous contacte et complète l'adresse avec vous.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Compléter l'adresse")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Envoyer à l'agence")),
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
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
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

    if (_pickup == null) return _missingAddress('où récupérer le colis');
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
      'Taille : ${_size.label} (${_size.hint.toLowerCase()})',
      if (details != null) details,
    ].join(' · ');

    final payload = <String, dynamic>{
      'type': _type.value,
      'pickup_address': _pickupAddress.text.trim(),
      'pickup_lat': _pickup!.latitude,
      'pickup_lng': _pickup!.longitude,
      'pickup_contact_name': orNull(_pickupName),
      'pickup_contact_phone': orNull(_pickupPhone),
      'dropoff_address': _dropoffAddress.text.trim(),
      'dropoff_lat': _dropoff!.latitude,
      'dropoff_lng': _dropoff!.longitude,
      'recipient_name': _recipientName.text.trim(),
      'recipient_phone': _recipientPhone.text.trim(),
      'package_description': description,
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
      error('Une erreur est survenue. Vérifiez dans Activité avant de recommencer.');
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
          ? 'Course créée. Payez pour la confirmer.'
          : 'Course créée. $failed photo(s) non envoyée(s), ajoutez-les depuis le suivi.'),
      backgroundColor: failed == 0 ? AppColors.success : AppColors.warning,
    ));
    Navigator.of(context).pop(delivery);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final otherSide = _sending;
    final top = MediaQuery.paddingOf(context).top;

    // Pas de retour pendant l'envoi (demande et photos) : la commande partirait sans suite.
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        body: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Stack(
                children: [
                  _RouteMap(pickup: _pickup, dropoff: _dropoff, fallback: _lome, height: 250 + top),
                  Positioned(
                    left: 12,
                    top: top + 8,
                    child: IconButton.filled(
                      tooltip: 'Retour',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.ink,
                        elevation: 2,
                        shadowColor: Colors.black26,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                ],
              ),
              // Feuille blanche qui chevauche la carte.
              Transform.translate(
                offset: const Offset(0, -24),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_sending ? 'Envoyer un colis' : 'Recevoir un colis', style: textTheme.headlineSmall),
                      const SizedBox(height: 14),
                      _RoleSwitch(sending: _sending, onChanged: _switchRole),
                      const SizedBox(height: 16),
                      _RouteCard(
                        pickup: _pickup == null ? null : _pickupAddress.text,
                        dropoff: _dropoff == null ? null : _dropoffAddress.text,
                        onPickup: () => _pick(pickup: true),
                        onDropoff: () => _pick(pickup: false),
                        onEditPickup: _pickup == null ? null : () => _editLandmark(pickup: true),
                        onEditDropoff: _dropoff == null ? null : () => _editLandmark(pickup: false),
                      ),
                      const SectionTitle('Choisissez une option'),
                      for (final s in ParcelSize.values)
                        _OptionRow(
                          icon: s.icon,
                          title: s.label,
                          subtitle: s.hint,
                          price: _quote == null ? null : formatFcfa(_quote!.deliveryFee),
                          selected: _size == s,
                          onTap: () {
                            setState(() => _size = s);
                            _refreshQuote();
                          },
                        ),
                      const SectionTitle('Quand ?'),
                      Row(
                        children: [
                          _WhenChip(
                            icon: Icons.bolt_rounded,
                            label: 'Maintenant',
                            selected: !_later,
                            onTap: () {
                              setState(() => _later = false);
                              _refreshQuote();
                            },
                          ),
                          const SizedBox(width: 10),
                          _WhenChip(
                            icon: Icons.event_rounded,
                            label: _later && _scheduledAt != null ? formatDateTime(_scheduledAt!) : 'Programmer',
                            selected: _later,
                            onTap: _pickSchedule,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Commande par simple photo du colis (l'agence complète le reste).
                      ListRow(
                        icon: Icons.photo_camera_outlined,
                        title: 'Commander par photo',
                        subtitle: "Une photo du colis suffit, l'agence s'occupe du reste",
                        onTap: _openPhotoProgramming,
                      ),
                      // Personne à l'autre bout (l'utilisateur est pré-rempli de son côté).
                      SectionTitle(otherSide ? 'Qui reçoit le colis ?' : 'Qui remet le colis ?'),
                      TextFormField(
                        key: ValueKey('name-$otherSide'),
                        controller: otherSide ? _recipientName : _pickupName,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Nom', prefixIcon: Icon(Icons.person_outline_rounded)),
                        validator: _required('Nom requis'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        key: ValueKey('phone-$otherSide'),
                        controller: otherSide ? _recipientPhone : _pickupPhone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Numéro de téléphone', prefixIcon: Icon(Icons.phone_outlined)),
                        validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 8 ? 'Numéro invalide' : null,
                      ),
                      const SectionTitle('Détails'),
                      TextFormField(
                        controller: _description,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: 'Que contient le colis ? (facultatif)',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _notes,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: 'Instructions pour le livreur (facultatif)',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ListRow(
                        icon: Icons.alarm_rounded,
                        title: _deadline == null ? 'Heure limite de livraison' : 'À livrer avant ${formatDateTime(_deadline!)}',
                        subtitle: _deadline == null ? 'Facultatif · le livreur est alerté si elle approche' : 'Touchez pour modifier',
                        onTap: _pickDeadline,
                        trailing: _deadline == null
                            ? null
                            : IconButton(
                                tooltip: 'Retirer',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => setState(() => _deadline = null),
                              ),
                      ),
                      SectionTitle(
                        'Photos des articles',
                        trailing: Text('${_photos.length}/$_maxPhotos · facultatif', style: textTheme.bodySmall),
                      ),
                      LocalPhotoGrid(
                        paths: _photos,
                        max: _maxPhotos,
                        onAdd: _addPhotos,
                        onRemove: (i) => setState(() => _photos.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Prix et bouton toujours visibles, au-dessus de la barre de navigation du téléphone.
        bottomNavigationBar: BottomActionBar(
          summary: _QuoteSummary(quote: _quote, loading: _quoting, failed: _quoteFailed, onRetry: _refreshQuote),
          children: [
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const ButtonProgress()
                  : Text(_quote == null ? 'Commander' : 'Commander · ${formatFcfa(_quote!.deliveryFee)}'),
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
  final double height;

  const _RouteMap({required this.pickup, required this.dropoff, required this.fallback, required this.height});

  @override
  Widget build(BuildContext context) {
    final points = <LatLng>[if (pickup != null) pickup!, if (dropoff != null) dropoff!];
    return SizedBox(
      height: height,
      child: FlutterMap(
        key: ValueKey(points.map((p) => '${p.latitude},${p.longitude}').join('|')),
        options: MapOptions(
          initialCenter: points.isEmpty ? fallback : points.first,
          initialZoom: points.isEmpty ? 12.5 : 15,
          initialCameraFit: points.length == 2
              ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.fromLTRB(60, 90, 60, 70))
              : null,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: [
          osmTiles(),
          if (points.length == 2) routeLine(points),
          MarkerLayer(markers: [
            if (pickup != null) stopMarker(pickup!, pickup: true),
            if (dropoff != null) stopMarker(dropoff!, pickup: false),
          ]),
          osmAttribution(),
        ],
      ),
    );
  }
}

/// Bascule « J'envoie / Je reçois » : rail gris, segment actif blanc avec ombre.
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
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: active ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 2))] : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: active ? AppColors.ink : AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: active ? AppColors.ink : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          option(true, Icons.north_east_rounded, "J'envoie"),
          option(false, Icons.south_west_rounded, 'Je reçois'),
        ],
      ),
    );
  }
}

/// Trajet : départ (rond) et arrivée (carré) reliés, chaque ligne ouvre le choix sur la carte.
class _RouteCard extends StatelessWidget {
  final String? pickup;
  final String? dropoff;
  final VoidCallback onPickup;
  final VoidCallback onDropoff;
  final VoidCallback? onEditPickup;
  final VoidCallback? onEditDropoff;

  const _RouteCard({
    required this.pickup,
    required this.dropoff,
    required this.onPickup,
    required this.onDropoff,
    required this.onEditPickup,
    required this.onEditDropoff,
  });

  @override
  Widget build(BuildContext context) {
    Widget row({
      required bool isPickup,
      required String? value,
      required String placeholder,
      required VoidCallback onTap,
      VoidCallback? onEdit,
    }) {
      final empty = value == null || value.isEmpty;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              StopDot(pickup: isPickup),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isPickup ? 'Départ' : 'Arrivée', style: Theme.of(context).textTheme.bodySmall),
                    Text(
                      empty ? placeholder : value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: empty ? FontWeight.w500 : FontWeight.w700,
                        color: empty ? AppColors.textHint : AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(tooltip: 'Préciser le repère', onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 20))
              else
                const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          row(isPickup: true, value: pickup, placeholder: 'Où récupérer le colis ?', onTap: onPickup, onEdit: onEditPickup),
          const Padding(padding: EdgeInsets.only(left: 30), child: Divider()),
          row(isPickup: false, value: dropoff, placeholder: 'Où livrer le colis ?', onTap: onDropoff, onEdit: onEditDropoff),
        ],
      ),
    );
  }
}

/// Option de taille, présentée comme les gammes de véhicules d'une app de mobilité (prix à droite).
class _OptionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? price;
  final bool selected;
  final VoidCallback onTap;

  const _OptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.price,
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
                  IconSquare(icon, size: 48, background: selected ? AppColors.accent : AppColors.surface),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (price != null)
                    Text(price!, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Puce « Maintenant » / « Programmer ».
class _WhenChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _WhenChip({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.ink : AppColors.surface,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: selected ? Colors.white : AppColors.ink),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.ink),
                ),
              ],
            ),
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
    final body = Theme.of(context).textTheme.bodyMedium;
    return SizedBox(
      height: 28,
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
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: body),
                    ),
                  ],
                ),
              ),
            )
          else if (quote == null)
            Expanded(
              child: Text('Indiquez départ et arrivée pour le prix.', maxLines: 1, overflow: TextOverflow.ellipsis, style: body),
            )
          else ...[
            const Icon(Icons.route_rounded, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(child: Text('${formatKm(quote!.distanceKm)} · paiement après la commande', style: body)),
          ],
        ],
      ),
    );
  }
}
