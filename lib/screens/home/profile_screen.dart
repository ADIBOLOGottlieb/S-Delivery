import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/support_phone.dart';
import '../../utils/colors.dart';
import '../../utils/launchers.dart';
import '../../widgets/photos.dart';
import '../../widgets/user_avatar.dart';
import '../auth/login_screen.dart';
import 'credentials_screen.dart';

/// Profil (partagé par le client et le livreur).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  /// Numéro de repli (fictif) : jamais affiché, le vrai numéro vient du serveur (support_phone).
  static const supportPhone = '+22890000000';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploading = false;

  /// Numéro de l'agence configuré par l'admin ; la carte « Contacter l'agence » est masquée sans lui.
  String? _supportPhone;

  @override
  void initState() {
    super.initState();
    SupportPhone.load(context.read<ApiClient>()).then((phone) {
      if (mounted && phone != null && phone != ProfileScreen.supportPhone) setState(() => _supportPhone = phone);
    });
  }

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

  /// Politique de confidentialité, ouverte dans le navigateur.
  Future<void> _openPrivacy() async {
    final url = await SupportPhone.privacyUrl(context.read<ApiClient>());
    if (mounted) await openWebPage(context, url);
  }

  /// Suppression définitive du compte (exigée par Google Play) : explication, mot de passe, puis retour à la connexion.
  Future<void> _deleteAccount() async {
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (deleted != true || !mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    messenger.showSnackBar(const SnackBar(content: Text('Votre compte a été supprimé.')));
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
                  child: Text(
                    (user?.roleLabel ?? 'Client').toUpperCase(),
                    style: textTheme.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
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
              leading: const Icon(Icons.key_outlined),
              title: const Text('Mes identifiants'),
              subtitle: const Text('Numéro, email, mot de passe'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CredentialsScreen())),
            ),
          ),
          if (_supportPhone != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.support_agent),
                title: const Text("Contacter l'agence"),
                subtitle: Text(_supportPhone!),
                trailing: const Icon(Icons.call),
                onTap: () => callPhone(context, _supportPhone!),
              ),
            ),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('À propos'),
                  subtitle: Text('VOOM Delivery · Lomé, Togo · v1.2.0'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Politique de confidentialité'),
                  trailing: const Icon(Icons.open_in_new, size: 20),
                  onTap: _openPrivacy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: AppColors.error),
            label: const Text('Se déconnecter', style: TextStyle(color: AppColors.error)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error)),
          ),
          const SizedBox(height: 32),
          Card(
            color: AppColors.error.withValues(alpha: 0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
            ),
            child: ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: AppColors.error),
              title: const Text('Supprimer mon compte', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
              subtitle: const Text('Définitif : vos données personnelles sont effacées.'),
              onTap: _deleteAccount,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialogue de suppression du compte : conséquences expliquées et mot de passe demandé.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Saisissez votre mot de passe.');
      return;
    }
    final auth = context.read<AuthService>();
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.deleteAccount(_password.text);
      navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 36),
      title: const Text('Supprimer mon compte ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cette action est définitive : vous ne pourrez plus vous connecter avec ce compte.\n\n'
              'Vos données personnelles (nom, téléphone, email, photo) sont effacées. '
              "L'historique des livraisons est conservé de façon anonyme pour la comptabilité de l'agence.\n\n"
              'Impossible tant qu\'une livraison est en cours.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: _obscure,
              enabled: !_busy,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                errorText: _error,
                errorMaxLines: 4,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Afficher' : 'Masquer',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _busy ? null : _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Supprimer'),
        ),
      ],
    );
  }
}
