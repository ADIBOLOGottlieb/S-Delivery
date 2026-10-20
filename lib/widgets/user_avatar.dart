import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/user.dart';
import '../utils/colors.dart';

/// Photo de profil, ou initiale sur fond gris à défaut.
class UserAvatar extends StatelessWidget {
  final User? user;
  final double radius;

  const UserAvatar({super.key, required this.user, this.radius = 24});

  @override
  Widget build(BuildContext context) =>
      Avatar(url: user?.avatarUrl, initial: user?.initial ?? 'U', radius: radius);
}

/// Avatar générique (client, livreur) : photo réseau ou initiale.
class Avatar extends StatelessWidget {
  final String? url;
  final String initial;
  final double radius;
  final Color background;
  final Color foreground;

  const Avatar({
    super.key,
    required this.url,
    required this.initial,
    this.radius = 24,
    this.background = AppColors.surfaceStrong,
    this.foreground = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    final letter = Text(
      initial,
      style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: radius * 0.8),
    );

    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      child: url == null
          ? letter
          : ClipOval(
              child: CachedNetworkImage(
                imageUrl: url!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                placeholder: (_, __) => letter,
                errorWidget: (_, __, ___) => letter,
              ),
            ),
    );
  }
}
