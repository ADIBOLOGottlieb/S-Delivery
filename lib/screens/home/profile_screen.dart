import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../utils/colors.dart';
import '../../utils/launchers.dart';
import '../../widgets/photos.dart';
import '../../widgets/user_avatar.dart';
import '../auth/login_screen.dart';

/// Profil (partagé par le client et le livreur).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static const supportPhone = '+22890000000';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploading = false;

  /// Ajoute, change ou retire la photo de profil.
  Future<void> _editPhoto() async {
    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);

    Future<void> run(Future<void> Function() action, String done) async {
      setState(() => _uploading = true);
      try {
        await action();
        messenger.showSnackBar(SnackBar(content: Text(done), backgroundColor: AppColors.success));
      } on ApiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
    }

    final path = await pickPhoto(
      context,
      onRemove: auth.user?.avatarUrl == null ? null : () => run(auth.removeAvatar, 'Photo retirée.'),
    );
    if (path != null) await run(() => auth.updateAvatar(path), 'Photo de profil mise à jour.');
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Déconnexion')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    await context.read<AuthService>().logout();
    navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final textTheme = Theme.of(context).textTheme;
    final hasPhoto = user?.avatarUrl != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                // Photo de profil : un appui pour ajouter / changer / retirer.
                Semantics(
                  button: true,
                  label: hasPhoto ? 'Changer la photo de profil' : 'Ajouter une photo de profil',
                  child: GestureDetector(
                    onTap: _uploading ? null : _editPhoto,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: UserAvatar(user: user, radius: 48),
                        ),
                        if (_uploading)
                          const Positioned.fill(
                            child: CircleAvatar(
                              backgroundColor: Color(0x88000000),
                              child: CircularProgressIndicator(color: AppColors.primary),
                            ),
                          ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.photo_camera, color: AppColors.primary, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(user?.name ?? 'Utilisateur',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(user?.phoneNumber ?? '', style: textTheme.bodyMedium?.copyWith(color: AppColors.onPrimary)),
                if (user?.email != null)
                  Text(user!.email!, style: textTheme.bodyMedium?.copyWith(color: AppColors.onPrimary)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.secondary, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (user?.isRegular ?? false) ...[
                        const Icon(Icons.star_rounded, color: AppColors.primary, size: 16),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        (user?.roleLabel ?? 'Client').toUpperCase(),
                        style: textTheme.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (user?.vehicle != null) ...[
                  const SizedBox(height: 8),
                  Text(user!.vehicle!, style: textTheme.bodyMedium?.copyWith(color: AppColors.onPrimary)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(hasPhoto ? 'Changer la photo de profil' : 'Ajouter une photo de profil'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _uploading ? null : _editPhoto,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text("Contacter l'agence"),
              subtitle: const Text(ProfileScreen.supportPhone),
              trailing: const Icon(Icons.call),
              onTap: () => callPhone(context, ProfileScreen.supportPhone),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('À propos'),
              subtitle: Text('VOOM Delivery · Lomé, Togo · v1.0.0'),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: AppColors.error),
            label: const Text('Se déconnecter', style: TextStyle(color: AppColors.error)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
