import '../../domain/chain.dart';
import '../../domain/models.dart';
import '../catalog/catalog.dart';
import '../catalog/product_matcher.dart';
import '../memo/memo_builder.dart';

/// What kind of gap a suggestion fills.
enum SuggestionKind { productMatch, quantity, rate, outletName, price, banglaName }

/// A proposed value for something that is missing or doubtful on an order.
/// Nothing is changed until the user applies it.
class Suggestion {
  Suggestion({
    required this.kind,
    required this.title,
    required this.detail,
    required this.confidence,
    this.itemIndex,
    this.productId,
    this.chain,
    this.numberValue,
    this.textValue,
  });

  final SuggestionKind kind;

  /// Short label, e.g. "Line 4: match product".
  final String title;

  /// What will be applied and where the value comes from.
  final String detail;

  /// 0..1; shown to the user so weak guesses are easy to reject.
  final double confidence;

  /// Index into the PO's items, for line-level suggestions.
  final int? itemIndex;

  /// Product to assign / update.
  final int? productId;

  /// Chain whose price list is updated.
  final Chain? chain;

  final double? numberValue;
  final String? textValue;

  bool selected = true;
}

/// Finds missing values on an order and proposes how to fill them:
///
/// * an unmatched PO line gets the closest catalogue product;
/// * a line with quantity or rate 0 gets a value computed from the other
///   columns, or the chain's list price;
/// * a blank memo name gets the default derived from the PO;
/// * for the chain's memo, catalogue products with no price get the other
///   chain's price, and products with no Bangla name get the name of a
///   sibling product (same English name, other size).
class SuggestionEngine {
  SuggestionEngine(this.catalog) : matcher = ProductMatcher(catalog);
  final Catalog catalog;
  final ProductMatcher matcher;

  List<Suggestion> forOrder(PurchaseOrder po, {required String outletDisplayName}) {
    final out = <Suggestion>[];
    final chain = po.chain == Chain.unknown ? Chain.dailyShopping : po.chain;

    if (outletDisplayName.trim().isEmpty) {
      final name = defaultOutletDisplayName(po.outletName, note: po.note);
      if (name.isNotEmpty) {
        out.add(Suggestion(kind: SuggestionKind.outletName, title: 'Name on memo is blank', detail: 'Use "$name" from the PO delivery address.', confidence: 0.9, textValue: name));
      }
    }

    for (var i = 0; i < po.items.length; i++) {
      final it = po.items[i];
      if (it.productId == null || catalog.byId(it.productId) == null) {
        final m = matcher.bestCandidate(it.name);
        if (m.product != null) {
          out.add(Suggestion(
            kind: SuggestionKind.productMatch,
            title: 'Line ${it.sl}: "${it.cleanName}" is not matched',
            detail: 'Match to ${m.product!.nameEn} ${m.product!.size} [${m.product!.dtCode}]. Name similarity ${(m.score * 100).round()}%.',
            confidence: m.score,
            itemIndex: i,
            productId: m.product!.id,
          ));
        }
      }
      if (it.quantity <= 0 && it.rate > 0 && it.total > 0) {
        final qty = (it.total + it.discount) / it.rate;
        out.add(Suggestion(kind: SuggestionKind.quantity, title: 'Line ${it.sl}: quantity is 0', detail: 'Total ${_f(it.total)} / rate ${_f(it.rate)} = ${_f(qty)}.', confidence: 0.85, itemIndex: i, numberValue: qty));
      }
      if (it.rate <= 0) {
        if (it.quantity > 0 && it.total > 0) {
          final rate = (it.total + it.discount) / it.quantity;
          out.add(Suggestion(kind: SuggestionKind.rate, title: 'Line ${it.sl}: rate is 0', detail: 'Total ${_f(it.total)} / quantity ${_f(it.quantity)} = ${_f(rate)}.', confidence: 0.85, itemIndex: i, numberValue: rate));
        } else if (it.productId != null) {
          final price = catalog.price(chain, it.productId!) ?? _otherChainPrice(chain, it.productId!);
          if (price != null) {
            out.add(Suggestion(kind: SuggestionKind.rate, title: 'Line ${it.sl}: rate is 0', detail: 'Use the list price ${_f(price)} from the catalogue.', confidence: 0.6, itemIndex: i, numberValue: price));
          }
        }
      }
    }

    // Gaps on the memo itself: blank prices and Bangla names.
    for (final p in catalog.productsFor(chain)) {
      if (catalog.price(chain, p.id) == null) {
        final other = _otherChainPrice(chain, p.id);
        if (other != null) {
          final otherChain = chain == Chain.bestBuy ? Chain.dailyShopping : Chain.bestBuy;
          out.add(Suggestion(
            kind: SuggestionKind.price,
            title: '${p.nameEn} ${p.size}: no ${chain.label} price',
            detail: 'Memo will print a blank price. Use the ${otherChain.label} price ${_f(other)}.',
            confidence: 0.4,
            productId: p.id,
            chain: chain,
            numberValue: other,
          ));
        }
      }
      if (p.nameBn.trim().isEmpty) {
        final sibling = catalog.products.firstWhere((q) => q.id != p.id && q.nameBn.trim().isNotEmpty && q.nameEn.toLowerCase() == p.nameEn.toLowerCase(), orElse: () => p);
        if (sibling.id != p.id) {
          out.add(Suggestion(kind: SuggestionKind.banglaName, title: '${p.nameEn} ${p.size}: no Bangla name', detail: 'Use "${sibling.nameBn}" from ${sibling.nameEn} ${sibling.size}.', confidence: 0.8, productId: p.id, textValue: sibling.nameBn));
        }
      }
    }
    out.sort((a, b) => b.confidence.compareTo(a.confidence));
    return out;
  }

  /// Blank prices for [chain] that the other chain's list can fill.
  List<Suggestion> blankPrices(Chain chain) => [
        for (final p in catalog.products)
          if (catalog.price(chain, p.id) == null && _otherChainPrice(chain, p.id) != null)
            Suggestion(
              kind: SuggestionKind.price,
              title: '${p.nameEn} ${p.size}',
              detail: 'Use ${_f(_otherChainPrice(chain, p.id)!)} from the ${chain == Chain.bestBuy ? Chain.dailyShopping.label : Chain.bestBuy.label} list.',
              confidence: 0.4,
              productId: p.id,
              chain: chain,
              numberValue: _otherChainPrice(chain, p.id),
            ),
      ];

  double? _otherChainPrice(Chain chain, int productId) {
    final other = chain == Chain.bestBuy ? Chain.dailyShopping : Chain.bestBuy;
    return catalog.price(other, productId);
  }

  static String _f(double v) => v.toStringAsFixed(2);
}
