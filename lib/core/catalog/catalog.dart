import '../../domain/chain.dart';
import '../../domain/models.dart';

/// In-memory view of the catalogue: products, per-chain settings and the
/// buyer-code aliases. Loaded from the database at start-up and refreshed
/// after every edit.
class Catalog {
  Catalog({required List<Product> products, required List<ChainProduct> chainProducts, required List<(Chain, String, int)> aliases})
      : products = List.unmodifiable([...products]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))),
        _byId = {for (final p in products) p.id: p},
        _byDtCode = {for (final p in products) p.dtCode: p},
        _chain = {for (final c in chainProducts) (c.chain, c.productId): c},
        _aliases = {for (final a in aliases) (a.$1, a.$2): a.$3};

  final List<Product> products;
  final Map<int, Product> _byId;
  final Map<String, Product> _byDtCode;
  final Map<(Chain, int), ChainProduct> _chain;
  final Map<(Chain, String), int> _aliases;

  Product? byId(int? id) => id == null ? null : _byId[id];
  Product? byDtCode(String code) => _byDtCode[code];

  /// Product for a buyer's code, via Daily Trading's own code or an alias.
  Product? byBuyerCode(Chain chain, String code) {
    final alias = _aliases[(chain, code)];
    if (alias != null) return _byId[alias];
    return _byDtCode[code];
  }

  ChainProduct? chainProduct(Chain chain, int productId) => _chain[(chain, productId)];

  double? price(Chain chain, int productId) => _chain[(chain, productId)]?.price;

  bool isIncluded(Chain chain, int productId) => _chain[(chain, productId)]?.included ?? (chain == Chain.dailyShopping);

  /// Products printed on a chain's memo, in print order.
  List<Product> productsFor(Chain chain) {
    final c = chain == Chain.unknown ? Chain.dailyShopping : chain;
    return products.where((p) => p.active && isIncluded(c, p.id)).toList();
  }
}
