import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/paged_api.dart';
import '../utils/colors.dart';

/// Liste paginée rechargeable : garde les anciennes données pendant le rechargement
/// (pas de spinner plein écran), distingue erreur et liste vide, et charge la page suivante (« Voir plus »).
class PagedLoader<T> extends ChangeNotifier {
  PagedLoader(this._fetch);

  final Future<PageResult<T>> Function(int page) _fetch;

  /// null tant que la première page n'a jamais été reçue.
  List<T>? items;

  /// Dernière erreur (rechargement ou page suivante) ; effacée au prochain succès.
  Object? error;
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = false;
  int _page = 1;
  int _generation = 0;
  bool _disposed = false;

  /// Message lisible d'une erreur quelconque.
  static String messageOf(Object? e) =>
      e is ApiException ? e.message : 'Une erreur est survenue. Vérifiez votre connexion et réessayez.';

  String get errorMessage => messageOf(error);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Recharge la première page. Sans effet si un rechargement est déjà en cours.
  Future<void> refresh() async {
    if (loading) return;
    final generation = ++_generation;
    loading = true;
    loadingMore = false;
    _notify();
    try {
      final page = await _fetch(1);
      if (generation != _generation) return;
      items = page.items;
      _page = page.page;
      hasMore = page.hasMore;
      error = null;
    } catch (e) {
      if (generation == _generation) error = e;
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  /// Page suivante, ajoutée à la fin de la liste.
  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore) return;
    final generation = _generation;
    loadingMore = true;
    _notify();
    try {
      final page = await _fetch(_page + 1);
      // Liste rechargée entre-temps : cette page n'est plus valable.
      if (generation != _generation) return;
      items = [...?items, ...page.items];
      _page = page.page;
      hasMore = page.hasMore;
      error = null;
    } catch (e) {
      if (generation == _generation) error = e;
    } finally {
      if (generation == _generation) {
        loadingMore = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Pied de liste : bouton « Voir plus » ou indicateur de chargement de la page suivante.
class LoadMoreFooter extends StatelessWidget {
  final PagedLoader<Object?> loader;

  const LoadMoreFooter({super.key, required this.loader});

  @override
  Widget build(BuildContext context) {
    if (loader.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
      );
    }
    if (!loader.hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: loader.loadMore,
          icon: const Icon(Icons.expand_more),
          label: const Text('Voir plus'),
        ),
      ),
    );
  }
}

/// Bandeau discret : actualisation impossible, les données affichées sont peut-être anciennes.
class StaleDataBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const StaleDataBanner({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}

/// Erreur de premier chargement (aucune donnée à montrer), avec « Réessayer ».
/// ListView : le « tirer pour rafraîchir » reste possible.
class ErrorRetryView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorRetryView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.cloud_off, size: 56, color: AppColors.textHint),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
        const SizedBox(height: 12),
        Center(child: OutlinedButton(onPressed: onRetry, child: const Text('Réessayer'))),
      ],
    );
  }
}
