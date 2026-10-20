import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/support_phone.dart';
import '../../utils/colors.dart';
import '../../utils/launchers.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/photos.dart';
import '../../widgets/ui.dart';
import '../../widgets/user_avatar.dart';
import '../auth/login_screen.dart';
import 'credentials_screen.dart';

/// Compte (partagé par le client et le livreur).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  /// Numéro de repli (fictif) : jamais affiché, le vrai numéro vient du serveur (support_phone).
  static const supportPhone = '+22890000000';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploading = false;

  /// Numéro de l'agence configuré par l'admin ; « Aide » est masquée sans lui.
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

  void _openCredentials() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CredentialsScreen()));

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final textTheme = Theme.of(context).textTheme;
    final hasPhoto = user?.avatarUrl != null;

    Widget quickTile(IconData icon, String label, VoidCallback? onTap) => Expanded(
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Icon(icon),
                    const SizedBox(height: 6),
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  ],
                ),
              ),
            ),
          ),
        );

    // Ouvert depuis l'espace livreur (écran poussé) : flèche retour ; dans l'onglet Compte : pas de barre.
    final pushed = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      appBar: pushed ? AppBar() : null,
      body: SafeArea(
        top: !pushed,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? 'Utilisateur', style: textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      Text(
                        [user?.roleLabel ?? 'Client', if (user?.vehicle != null) user!.vehicle!].join(' · '),
                        style: textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                // Photo de profil : un appui pour ajouter / changer / retirer.
                Semantics(
                  button: true,
                  label: hasPhoto ? 'Changer la photo de profil' : 'Ajouter une photo de profil',
                  child: GestureDetector(
                    onTap: _uploading ? null : _editPhoto,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        UserAvatar(user: user, radius: 34),
                        if (_uploading)
                          const Positioned.fill(
                            child: CircleAvatar(
                              backgroundColor: Color(0x88000000),
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.ink,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                quickTile(Icons.support_agent_rounded, 'Aide', _supportPhone == null ? null : () => callPhone(context, _supportPhone!)),
                const SizedBox(width: 10),
                quickTile(Icons.key_outlined, 'Identifiants', _openCredentials),
                const SizedBox(width: 10),
                quickTile(Icons.privacy_tip_outlined, 'Confidentialité', _openPrivacy),
              ],
            ),
            const SectionTitle('Compte'),
            ListRow(
              icon: Icons.phone_outlined,
              title: user?.phoneNumber ?? '',
              subtitle: user?.email ?? 'Numéro de connexion',
              onTap: _openCredentials,
            ),
            ListRow(
              icon: Icons.photo_camera_outlined,
              title: hasPhoto ? 'Changer la photo de profil' : 'Ajouter une photo de profil',
              subtitle: 'Aide le livreur et le client à vous reconnaître',
              onTap: _uploading ? null : _editPhoto,
            ),
            if (_supportPhone != null)
              ListRow(
                icon: Icons.call_outlined,
                title: "Contacter l'agence",
                subtitle: _supportPhone,
                onTap: () => callPhone(context, _supportPhone!),
              ),
            const SectionTitle('Application'),
            ListRow(icon: Icons.privacy_tip_outlined, title: 'Politique de confidentialité', onTap: _openPrivacy),
            ListRow(icon: Icons.logout_rounded, title: 'Se déconnecter', onTap: _logout),
            ListRow(
              icon: Icons.delete_outline_rounded,
              title: 'Supprimer mon compte',
              subtitle: 'Définitif : vos données personnelles sont effacées.',
              color: AppColors.error,
              onTap: _deleteAccount,
            ),
            const SizedBox(height: 32),
            const Center(child: SDeliveryLogo(height: 26)),
            const SizedBox(height: 8),
            Center(child: Text('Lomé, Togo · v2.0.0', style: textTheme.bodySmall)),
          ],
        ),
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
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 44),
          ),
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Supprimer'),
        ),
      ],
    );
  }
}
