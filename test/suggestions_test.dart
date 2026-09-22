import 'package:daily_trading_bill_generator/core/catalog/seed_catalog.dart';
import 'package:daily_trading_bill_generator/core/suggest/suggestions.dart';
import 'package:daily_trading_bill_generator/domain/chain.dart';
import 'package:daily_trading_bill_generator/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalog = SeedCatalog.build();
  final engine = SuggestionEngine(catalog);

  PurchaseOrder po(List<PoItem> items) => PurchaseOrder(
        poNumber: 'PO-12000-01-26-000001',
        chain: Chain.bestBuy,
        poDate: '16-Sep-2026',
        purchaser: 'x',
        outletName: 'BBUY-Test-Outlet',
        address: '',
        supplier: '',
        items: items,
        declaredTotal: null,
        amountInWords: '',
        deliverySchedule: '',
        note: '',
        sourceFile: 't.pdf',
        pages: [1],
      );

  test('suggests a product for an unmatched line, quantity and rate from the other columns, and a blank name', () {
    final items = [
      PoItem(sl: 1, code: '111111', name: 'Daily Shopping Cardamon 25gm', unit: 'Piece', quantity: 12, rate: 166.05, discount: 0, total: 1992.60),
      PoItem(sl: 2, code: '895672', name: 'Daily Shopping Almond 100gm', unit: 'Piece', quantity: 0, rate: 213.20, discount: 0, total: 2558.40, productId: catalog.byDtCode('5000000561')!.id),
      PoItem(sl: 3, code: '895195', name: 'Daily Shopping Almond 50gm', unit: 'Piece', quantity: 12, rate: 0, discount: 0, total: 1150.20, productId: catalog.byDtCode('5000000562')!.id),
    ];
    final s = engine.forOrder(po(items), outletDisplayName: '');
    final byKind = {for (final x in s) x.kind: x};
    expect(byKind[SuggestionKind.outletName]!.textValue, 'BBUY Test Outlet');
    expect(catalog.byId(byKind[SuggestionKind.productMatch]!.productId)!.nameEn, 'Cardamom');
    expect(byKind[SuggestionKind.productMatch]!.itemIndex, 0);
    expect(byKind[SuggestionKind.quantity]!.numberValue, closeTo(12, 0.001));
    expect(byKind[SuggestionKind.rate]!.numberValue, closeTo(95.85, 0.001));
    // Best Buy has blank prices that Daily Shopping can fill (e.g. Ajwain).
    expect(s.where((x) => x.kind == SuggestionKind.price && x.title.startsWith('Ajwain')), isNotEmpty);
    // Sorted by confidence, strongest first.
    for (var i = 1; i < s.length; i++) {
      expect(s[i - 1].confidence >= s[i].confidence, isTrue);
    }
  });

  test('blank price list for Best Buy comes from the Daily Shopping list', () {
    final s = engine.blankPrices(Chain.bestBuy);
    expect(s.length, greaterThan(15));
    expect(s.every((x) => x.chain == Chain.bestBuy && x.numberValue != null), isTrue);
    expect(engine.blankPrices(Chain.dailyShopping), isEmpty);
  });
}
