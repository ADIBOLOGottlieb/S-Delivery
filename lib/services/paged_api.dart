import '../models/chat.dart';
import '../models/delivery.dart';
import 'api_client.dart';

/// Une page d'une liste paginée par Laravel (?page=N).
class PageResult<T> {
  final List<T> items;
  final int page;
  final bool hasMore;

  const PageResult({required this.items, required this.page, required this.hasMore});
}

/// Listes paginées (« Voir plus ») : livraisons du client, discussions, courses du livreur.
class PagedApi {
  PagedApi(this._api);

  final ApiClient _api;

  Future<PageResult<T>> _page<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    required int page,
    Map<String, String> query = const {},
  }) async {
    final data = await _api.get(path, query: {...query, if (page > 1) 'page': '$page'}) as Map<String, dynamic>;
    return parsePage(data, parse, page: page);
  }

  /// Lit la réponse paginée (data + meta/links) ; sans métadonnées, on considère qu'il n'y a pas de suite.
  static PageResult<T> parsePage<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) parse, {
    required int page,
  }) {
    final items = (data['data'] as List? ?? const []).map((e) => parse(e as Map<String, dynamic>)).toList();
    final meta = data['meta'];
    final links = data['links'];
    var hasMore = false;
    if (meta is Map<String, dynamic> && meta['current_page'] is num && meta['last_page'] is num) {
      hasMore = (meta['current_page'] as num) < (meta['last_page'] as num);
    } else if (links is Map<String, dynamic>) {
      hasMore = links['next'] != null;
    }
    return PageResult(items: items, page: page, hasMore: hasMore);
  }

  Future<PageResult<Delivery>> myDeliveries({int page = 1}) => _page('/deliveries', Delivery.fromJson, page: page);

  Future<PageResult<ChatRequest>> chatRequests({int page = 1}) =>
      _page('/requests', ChatRequest.fromJson, page: page);

  Future<PageResult<Delivery>> courierDeliveries({bool history = false, int page = 1}) => _page(
        '/courier/deliveries',
        Delivery.fromJson,
        page: page,
        query: history ? const {'scope': 'history'} : const {},
      );
}
