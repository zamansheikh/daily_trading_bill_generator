/// A retail chain that sends purchase orders to Daily Trading Corporation.
///
/// Each chain has its own product code scheme, its own subset of the
/// catalogue and its own price list, so almost everything downstream of the
/// parser is keyed by chain.
enum Chain {
  dailyShopping('daily_shopping', 'Daily Shopping'),
  bestBuy('best_buy', 'Best Buy (BBUY)'),
  unknown('unknown', 'Unknown');

  const Chain(this.id, this.label);

  /// Stable identifier used in the database.
  final String id;

  /// Human readable label for the UI.
  final String label;

  static Chain fromId(String? id) =>
      Chain.values.firstWhere((c) => c.id == id, orElse: () => Chain.unknown);

  /// Detects the chain from the signals a purchase order carries.
  ///
  /// The outlet name is the strongest signal ("BBUY-Mogbazar", "Daily
  /// Shopping - Nikunja"). The product code length is the fallback: Best Buy
  /// uses its own 6-digit codes while Daily Shopping orders carry Daily
  /// Trading's 10-digit codes.
  static Chain detect({
    required String outletName,
    required String poNumber,
    required Iterable<String> codes,
  }) {
    final outlet = outletName.toLowerCase();
    if (outlet.contains('bbuy') || outlet.contains('best buy')) {
      return Chain.bestBuy;
    }
    if (outlet.contains('daily shopping')) return Chain.dailyShopping;
    if (poNumber.startsWith('PO-12000')) return Chain.bestBuy;
    if (poNumber.startsWith('PO-3800') || poNumber.startsWith('PO-001')) {
      return Chain.dailyShopping;
    }
    final lengths = codes.map((c) => c.length).toSet();
    if (lengths.length == 1) {
      if (lengths.first == 6) return Chain.bestBuy;
      if (lengths.first == 10) return Chain.dailyShopping;
    }
    return Chain.unknown;
  }
}
