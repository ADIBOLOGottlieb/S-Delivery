import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/colors.dart';

/// Demande au client d'où vient la photo (appareil photo ou galerie), puis la compresse.
/// Renvoie le chemin du fichier, ou null si annulé. Avec [onRemove], propose aussi « Retirer ».
Future<String?> pickPhoto(BuildContext context, {VoidCallback? onRemove}) async {
  final source = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Icon(Icons.photo_camera, color: AppColors.onPrimary),
            ),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.secondary,
              child: Icon(Icons.photo_library, color: AppColors.primary),
            ),
            title: const Text('Choisir dans la galerie'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          if (onRemove != null)
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x1AF44336),
                child: Icon(Icons.delete_outline, color: AppColors.error),
              ),
              title: const Text('Retirer la photo', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (source == 'remove') {
    onRemove?.call();
    return null;
  }
  if (source is! ImageSource) return null;

  // Photos réduites (≈ 200 Ko) : envoi rapide même en 3G.
  final file = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 75);
  return file?.path;
}

/// Photo d'un colis prise avec l'appareil photo.
/// [keep] : photos déjà choisies, mises de côté au cas où Android ferme l'app pendant la prise de vue
/// (fréquent sur les téléphones à petite mémoire) ; elles sont alors rendues par [PhotoDraft.recover].
Future<String?> pickPhotoFromCamera({List<String> keep = const []}) async {
  await PhotoDraft._save(keep);
  final file = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 1280,
    maxHeight: 1280,
    imageQuality: 75,
    requestFullMetadata: false,
  );
  await PhotoDraft.clear();
  return file?.path;
}

/// Photos d'une demande en cours, conservées pendant que l'appareil photo est ouvert.
///
/// Sur Android, le système peut fermer l'app pour libérer de la mémoire pendant la prise de vue :
/// elle redémarre alors sur l'accueil. [recover] rend les photos déjà prises et celle qui venait
/// d'être prise (récupérée par ImagePicker.retrieveLostData), pour reprendre là où on en était.
class PhotoDraft {
  static const _storage = FlutterSecureStorage();
  static const _key = 'photo_draft';

  static Future<void> _save(List<String> paths) async {
    try {
      // Marqueur présent même sans photo : signale qu'une prise de vue de colis est en cours.
      await _storage.write(key: _key, value: jsonEncode(paths));
    } catch (_) {}
  }

  /// Photos à reprendre après un redémarrage forcé, ou liste vide.
  static Future<List<String>> recover() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return const [];
      await clear();
      final kept = (jsonDecode(raw) as List).cast<String>();
      final lost = await ImagePicker().retrieveLostData();
      final taken = lost.isEmpty ? const <String>[] : [for (final f in lost.files ?? const <XFile>[]) f.path];
      return [...kept, ...taken].where((p) => File(p).existsSync()).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

/// Plusieurs photos de la galerie d'un coup (articles à livrer).
Future<List<String>> pickPhotosFromGallery({int limit = 6}) async {
  if (limit <= 0) return const [];
  final picker = ImagePicker();
  // pickMultiImage exige une limite d'au moins 2.
  if (limit == 1) {
    final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1280, maxHeight: 1280, imageQuality: 75);
    return file == null ? const [] : [file.path];
  }
  final files = await picker.pickMultiImage(maxWidth: 1280, maxHeight: 1280, imageQuality: 75, limit: limit);
  return files.take(limit).map((f) => f.path).toList();
}

/// Grille de photos locales à envoyer, avec ajout et suppression.
class LocalPhotoGrid extends StatelessWidget {
  final List<String> paths;
  final int max;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const LocalPhotoGrid({
    super.key,
    required this.paths,
    required this.onAdd,
    required this.onRemove,
    this.max = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < paths.length; i++)
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(File(paths[i]), width: 92, height: 92, fit: BoxFit.cover),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Material(
                  color: AppColors.secondary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onRemove(i),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        if (paths.length < max)
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primaryDark, width: 1.5),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: AppColors.secondary),
                  SizedBox(height: 4),
                  Text('Ajouter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Miniatures défilantes de photos en ligne ; un appui ouvre la visionneuse plein écran.
class PhotoStrip extends StatelessWidget {
  final List<String> urls;
  final double size;

  const PhotoStrip({super.key, required this.urls, this.size = 84});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => openPhotoViewer(context, urls, initial: i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: urls[i],
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.surface),
              errorWidget: (_, __, ___) =>
                  Container(color: AppColors.surface, child: const Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      ),
    );
  }
}

void openPhotoViewer(BuildContext context, List<String> urls, {int initial = 0}) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PhotoViewer(urls: urls, initial: initial),
  ));
}

class _PhotoViewer extends StatelessWidget {
  final List<String> urls;
  final int initial;

  const _PhotoViewer({required this.urls, required this.initial});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: PageView.builder(
        controller: PageController(initialPage: initial),
        itemCount: urls.length,
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 4,
          child: Center(child: CachedNetworkImage(imageUrl: urls[i], fit: BoxFit.contain)),
        ),
      ),
    );
  }
}
