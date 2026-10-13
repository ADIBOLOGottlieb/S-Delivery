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

Future<void> _launch(BuildContext context, Uri uri, String error) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    messenger.showSnackBar(SnackBar(content: Text(error), backgroundColor: AppColors.error));
  }
}
