import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'colors.dart';

/// Ouvre Google Maps en mode itinéraire vers [lat],[lng] (depuis la position actuelle).
Future<void> openNavigation(BuildContext context, double lat, double lng) {
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
  );
  return _launch(context, uri, 'Impossible d\'ouvrir Google Maps.');
}

/// Affiche un point sur Google Maps (position partagée dans la discussion).
Future<void> openMapAt(BuildContext context, double lat, double lng) {
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  return _launch(context, uri, 'Impossible d\'ouvrir la carte.');
}

Future<void> callPhone(BuildContext context, String phone) {
  final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
  return _launch(context, uri, 'Impossible de lancer l\'appel.');
}

/// Prépare un SMS vers [phone] (ex. code de remise transmis au destinataire).
Future<void> sendSms(BuildContext context, String phone, String body) {
  final uri = Uri(scheme: 'sms', path: phone.replaceAll(' ', ''), queryParameters: {'body': body});
  return _launch(context, uri, "Impossible d'ouvrir les messages.");
}

/// Ouvre WhatsApp vers [phone] avec un message prérempli.
Future<void> openWhatsApp(BuildContext context, String phone, {String? message}) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  final uri = Uri.https('wa.me', '/$digits', {if (message != null && message.isNotEmpty) 'text': message});
  return _launch(context, uri, 'Impossible d\'ouvrir WhatsApp.');
}

/// Ouvre une page web dans le navigateur (ex. politique de confidentialité).
Future<void> openWebPage(BuildContext context, String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lien invalide.'), backgroundColor: AppColors.error),
    );
    return Future.value();
  }
  return _launch(context, uri, 'Impossible d\'ouvrir la page.');
}

Future<void> _launch(BuildContext context, Uri uri, String error) async {
  final messenger = ScaffoldMessenger.of(context);
  bool ok;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Aucune application pour ce lien (ex. WhatsApp absent).
    ok = false;
  }
  if (!ok) {
    messenger.showSnackBar(SnackBar(content: Text(error), backgroundColor: AppColors.error));
  }
}
