import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/delivery.dart';
import '../../models/product.dart';
import '../../services/delivery_service.dart';
import '../../utils/colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/skeleton.dart';
import 'delivery_detail_screen.dart';
import 'new_delivery_screen.dart';

enum ProductCategory {
  shopping('shopping', 'Shopping', AppColors.primary, AppColors.onPrimary, Icons.shopping_bag),
  agro('agro', 'Courses alimentaires', AppColors.success, AppColors.background, Icons.shopping_basket);

  const ProductCategory(this.value, this.label, this.color, this.onColor, this.icon);
  final String value;
  final String label;
  final Color color;
  final Color onColor;
  final IconData icon;
}

/// Onglet du catalogue : tout, les packs, ou une sous-catégorie nommée par l'admin.
class _Tab {
  final String label;
  final IconData icon;
  final int? subcategoryId;
  final bool packs;

  const _Tab(this.label, this.icon, {this.subcategoryId, this.packs = false});
}

/// Ouvre la fiche d'un produit puis, si le client commande, le formulaire de livraison.
Future<void> showProductSheet(BuildContext context, Product product, {Color color = AppColors.primary}) async {
  final quantity = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ProductSheet(product: product),
  );
  if (quantity == null || !context.mounted) return;

  final created = await Navigator.of(context).push<Delivery>(
    MaterialPageRoute(builder: (_) => NewDeliveryScreen(product: product, quantity: quantity)),
  );
  if (created != null && context.mounted) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryDetailScreen(deliveryId: created.id)));
  }
}

/// Catalogue de la marketplace (produits et packs gérés par l'admin).
/// Agroalimentaire : onglets verticaux par sous-catégorie.
class ProductCatalogScreen extends StatefulWidget {
  final ProductCategory category;

  const ProductCatalogScreen({super.key, required this.category});

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  List<_Tab> _tabs = const [_Tab('Tout', Icons.apps)];
  int _tab = 0;
  late Future<List<Product>> _products;
  String _search = '';
  Timer? _debounce;

  bool get _vertical => widget.category == ProductCategory.agro;

  @override
  void initState() {
    super.initState();
    _load();
    if (_vertical) _loadTabs();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadTabs() async {
    try {
      final (subs, hasPacks) = await context.read<DeliveryService>().subcategories(widget.category.value);
      if (!mounted) return;
      setState(() {
        // Sous-onglets nommés par l'admin, puis « Packs » en dernier.
        _tabs = [
          const _Tab('Tout', Icons.apps),
          for (final s in subs) _Tab(s.name, _iconFor(s.name), subcategoryId: s.id),
          if (hasPacks) const _Tab('Packs', Icons.card_giftcard, packs: true),
        ];
      });
    } catch (_) {
      // Sans onglets, le catalogue reste utilisable (« Tout »).
    }
  }

  void _load() {
    final tab = _tabs[_tab.clamp(0, _tabs.length - 1)];
    _products = context.read<DeliveryService>().products(
          category: widget.category.value,
          subcategoryId: tab.subcategoryId,
          type: tab.packs ? 'pack' : null,
          search: _search,
        );
  }

  void _select(int i) {
    if (i == _tab) return;
    setState(() {
      _tab = i;
      _load();
    });
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search = value.trim();
      if (mounted) setState(_load);
    });
  }

  /// Icône devinée à partir du nom choisi par l'admin.
  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('poisson') || n.contains('mer')) return Icons.set_meal;
    if (n.contains('viande') || n.contains('volaille')) return Icons.kebab_dining;
    if (n.contains('conserve')) return Icons.inventory_2;
    if (n.contains('céréal') || n.contains('grain') || n.contains('riz')) return Icons.grass;
    if (n.contains('légume')) return Icons.eco;
    if (n.contains('tubercule') || n.contains('igname')) return Icons.spa;
    if (n.contains('fruit')) return Icons.local_florist;
    if (n.contains('œuf')) return Icons.egg_alt;
    if (n.contains('huile') || n.contains('transform')) return Icons.water_drop;
    return Icons.category;
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final grid = _ProductGrid(
      future: _products,
      icon: cat.icon,
      color: cat.color,
      onRefresh: () async {
        setState(_load);
        await _products.catchError((_) => <Product>[]);
      },
      onRetry: () => setState(_load),
    );

    return Scaffold(
      appBar: AppBar(title: Text(cat.label)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Rechercher un produit…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _vertical
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _VerticalTabs(tabs: _tabs, selected: _tab, color: cat.color, onSelect: _select),
                      Expanded(child: grid),
                    ],
                  )
                : grid,
          ),
        ],
      ),
    );
  }
}

/// Onglets verticaux (à gauche), façon applications de courses.
class _VerticalTabs extends StatelessWidget {
  final List<_Tab> tabs;
  final int selected;
  final Color color;
  final ValueChanged<int> onSelect;

  const _VerticalTabs({required this.tabs, required this.selected, required this.color, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      color: AppColors.surface,
      child: ListView.builder(
        padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
        itemCount: tabs.length,
        itemBuilder: (context, i) {
          final tab = tabs[i];
          final active = i == selected;
          return InkWell(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.card : Colors.transparent,
                border: Border(left: BorderSide(color: active ? color : Colors.transparent, width: 4)),
              ),
              child: Column(
                children: [
                  Icon(tab.icon, color: active ? color : AppColors.textSecondary, size: 24),
                  const SizedBox(height: 6),
                  Text(
                    tab.label,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.2,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  final Future<List<Product>> future;
  final IconData icon;
  final Color color;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  const _ProductGrid({
    required this.future,
    required this.icon,
    required this.color,
    required this.onRefresh,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: FutureBuilder<List<Product>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return GridView.count(
              padding: const EdgeInsets.all(12),
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.7,
              children: List.generate(6, (_) => const Skeleton(height: 200, radius: 16)),
            );
          }
          if (snapshot.hasError) {
            return ListView(children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  Text(snapshot.error.toString(), textAlign: TextAlign.center),
                  TextButton(onPressed: onRetry, child: const Text('Réessayer')),
                ]),
              ),
            ]);
          }
          final products = snapshot.data!;
          if (products.isEmpty) {
            return ListView(children: const [
              Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Aucun produit ici pour le moment.'))),
            ]);
          }
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 16 + MediaQuery.paddingOf(context).bottom),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.7,
            ),
            itemCount: products.length,
            itemBuilder: (context, i) => _ProductCard(
              product: products[i],
              icon: icon,
              onTap: () => showProductSheet(context, products[i], color: color),
            ),
          );
        },
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String? url;
  final IconData icon;

  const _ProductImage({required this.url, required this.icon});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Icon(icon, size: 42, color: AppColors.textHint),
    );
    if (url == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => placeholder,
    );
  }
}

class _PackBadge extends StatelessWidget {
  const _PackBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.secondary, borderRadius: BorderRadius.circular(8)),
      child: const Text('PACK', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final IconData icon;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ProductImage(url: product.imageUrl, icon: product.isPack ? Icons.card_giftcard : icon),
                  if (product.isPack) const Positioned(left: 8, top: 8, child: _PackBadge()),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              // Format court sur les petites cartes : « 2 000 F ».
                              text: formatFcfa(product.price).replaceAll('FCFA', 'F'),
                              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            ),
                            if (product.unit != null)
                              TextSpan(
                                text: ' /${product.unit}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(9)),
                        child: const Icon(Icons.add, size: 18, color: AppColors.onPrimary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fiche produit + choix de la quantité ; renvoie la quantité choisie.
class _ProductSheet extends StatefulWidget {
  final Product product;

  const _ProductSheet({required this.product});

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (p.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(height: 180, child: _ProductImage(url: p.imageUrl, icon: Icons.image)),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (p.isPack) const Padding(padding: EdgeInsets.only(right: 8), child: _PackBadge()),
                Expanded(child: Text(p.name, style: Theme.of(context).textTheme.headlineSmall)),
              ],
            ),
            if (p.vendorName != null) Text(p.vendorName!, style: Theme.of(context).textTheme.bodyMedium),
            if (p.description != null) ...[
              const SizedBox(height: 8),
              Text(p.description!),
            ],
            if (p.items.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Contenu du pack', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final item in p.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    const Icon(Icons.check_circle, size: 16, color: AppColors.success),
                    const SizedBox(width: 6),
                    Expanded(child: Text(item.name)),
                    Text(
                      '× ${item.quantity}${item.unit != null ? ' ${item.unit}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton.outlined(
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('$_quantity ${p.unit ?? ''}', style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton.outlined(
                  onPressed: _quantity < 100 ? () => setState(() => _quantity++) : null,
                  icon: const Icon(Icons.add),
                ),
                const Spacer(),
                Text(formatFcfa(p.price * _quantity),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(_quantity),
              icon: const Icon(Icons.local_shipping),
              label: const Text('Commander et me faire livrer'),
            ),
          ],
        ),
      ),
    );
  }
}
