import 'dart:io';

import 'package:daily_trading_bill_generator/core/catalog/product_matcher.dart';
import 'package:daily_trading_bill_generator/core/catalog/seed_catalog.dart';
import 'package:daily_trading_bill_generator/core/memo/bengali.dart';
import 'package:daily_trading_bill_generator/core/memo/memo_builder.dart';
import 'package:daily_trading_bill_generator/core/memo/memo_pdf.dart';
import 'package:daily_trading_bill_generator/core/parsing/po_parser.dart';
import 'package:daily_trading_bill_generator/domain/chain.dart';
import 'package:flutter_test/flutter_test.dart';

const outDir = String.fromEnvironment('MEMO_OUT', defaultValue: 'build/test_memos');

void main() {
  final catalog = SeedCatalog.build();
  final matcher = ProductMatcher(catalog);
  final parser = PoParser();

  test('bengali digits', () {
    expect(toBengaliDigits('72'), '৭২');
    expect(toBengaliDigits('a1'), 'a১');
  });

  test('seed catalogue has 78 products, 71 on Best Buy memos, unique codes', () {
    expect(catalog.products.length, 78);
    expect(catalog.productsFor(Chain.dailyShopping).length, 78);
    expect(catalog.productsFor(Chain.bestBuy).length, 71);
    expect(catalog.products.map((p) => p.dtCode).toSet().length, 78);
  });

  test('name matcher handles the spellings seen on POs', () {
    String? m(String n) => matcher.matchByName(n).product?.let((p) => '${p.nameEn} ${p.size}');
    expect(m('Daily Shopping Cashew 100gm'), 'Cashew Nut 100gm');
    expect(m('Daily Shopping Tasting Salt 100gm'), 'Testing Salt 100gm');
    expect(m('Daily Shopping Testing Solt 50 gm'), 'Testing Salt 50gm');
    expect(m('Daily Shopping Chick-Peas flour 500gm'), 'Chik peas flour 500gm');
    expect(m('Daily Shopping Isobgul Bhushi(Bran) 50gm'), 'Isobgul Bhushi 50gm');
    expect(m('Daily Shopping Fenugreek Ground 80gm'), 'Ground Mathi 80gm');
    expect(m('Daily Shopping Mace Ground 20gm'), 'Ground Mace 20gm');
    expect(m('Daily Shopping Peanut Fried (White)100gm'), 'Peanut Fried 100gm');
    expect(m('Daily Shopping Rice Flour 1Kg'), 'Rice Flour 1KG');
    expect(m('Daily Shopping Sagudana 100g'), 'Sagudana 100gm');
    expect(m('Daily Shopping Chines Papor 200gm'), 'Chinese Papor 200gm');
    expect(m('Daily Shopping China Grass 5gm'), 'Chaina Grass 5gm');
    expect(m('Daily Shopping Ground Garam Masala 50gm'), 'Ground Garam mashala 50gm');
    expect(m('Daily Shopping Black Pepper 50 gm'), 'Black pepper 50gm');
    expect(m('Daily Shopping Coriander whole 100gm'), 'Coriander Whole 100gm');
    expect(m('Daily Shopping Almond 100gm'), 'Almond 100gm');
    expect(m('Daily Shopping Almond 50gm'), 'Almond 50gm');
    expect(m('Something Unknown 999gm'), isNull);
  });

  test('every PO line in both sample files matches a catalogue product', () {
    for (final f in ['sample_pdf/inputs/Daily Trading PO DSD 16.09.26.pdf', 'sample_pdf/inputs/DT PO (2).pdf']) {
      final r = parser.parseBytes(File(f).readAsBytesSync(), sourceFile: f);
      final unmatched = <String>[];
      for (final o in r.orders) {
        for (final it in o.items) {
          final m = matcher.match(o.chain, it);
          if (m.product == null) unmatched.add('${o.poNumber}: ${it.code} ${it.name}');
          it.productId = m.product?.id;
          final poSize = ProductMatcher.extractSize(it.name);
          if (m.product != null && poSize.isNotEmpty) {
            // Size on the PO must agree with the matched product.
            expect(ProductMatcher.normalizeSize(poSize),
                ProductMatcher.normalizeSize(m.product!.size),
                reason: '${it.name} -> ${m.product!.nameEn} ${m.product!.size}');
          }
        }
      }
      expect(unmatched, isEmpty);
    }
  });

  test('memo for the reference PO reproduces the reference memo values', () async {
    const f = 'sample_pdf/inputs/Daily Trading PO DSD 16.09.26.pdf';
    final r = parser.parseBytes(File(f).readAsBytesSync(), sourceFile: f);
    final po = r.orders.last; // PO-12000-01-26-011532 -> memo 9808
    for (final it in po.items) {
      it.productId = matcher.match(po.chain, it).product?.id;
    }
    final doc = MemoBuilder(catalog).build(
      po,
      memoNumber: 9808,
      supplyDate: DateTime(2026, 9, 19),
      outletDisplayName: 'BBUY Grocery Mogbazar Wireless Gate',
    );
    expect(doc.rows.length, 71);
    expect(doc.total, closeTo(25158.60, 0.001));
    MemoRow row(String name, String size) => doc.rows.firstWhere((r) => r.nameEn == name && r.size == size);
    expect(row('Almond', '100gm').quantity, 12);
    expect(row('Almond', '100gm').price, 213.20);
    expect(row('Almond', '100gm').amount, closeTo(2558.40, 0.001));
    expect(row('Ajwain', '50gm').quantity, isNull);
    expect(row('Ajwain', '50gm').price, isNull);
    expect(row('Alubokhara', '100gm').price, 195.00);
    expect(row('Mace', '20gm').quantity, 12);
    expect(row('Tokma', '50gm').amount, closeTo(219.00, 0.001));
    expect(row('Yellow Mustard', '100gm').sl, 71);

    final banner = File('assets/images/memo_banner.png').readAsBytesSync();
    final bytes = await MemoPdf(bannerImage: banner).render(doc);
    Directory(outDir).createSync(recursive: true);
    File('$outDir/9808(BBUY Grocery Mogbazar Wireless Gate).pdf').writeAsBytesSync(bytes);
    expect(bytes.length, greaterThan(10000));

    // A Daily Shopping memo (78 rows) must also fit on one page.
    const f2 = 'sample_pdf/inputs/DT PO (2).pdf';
    final r2 = parser.parseBytes(File(f2).readAsBytesSync(), sourceFile: f2);
    final po2 = r2.orders.first;
    for (final it in po2.items) {
      it.productId = matcher.match(po2.chain, it).product?.id;
    }
    final doc2 = MemoBuilder(catalog).build(po2, memoNumber: 9900, supplyDate: DateTime(2026, 9, 6), outletDisplayName: defaultOutletDisplayName(po2.outletName));
    expect(doc2.rows.length, 78);
    expect(doc2.rows.where((r) => r.quantity != null).length, po2.items.length);
    final bytes2 = await MemoPdf(bannerImage: banner).render(doc2);
    File('$outDir/9900(${doc2.outletDisplayName}).pdf').writeAsBytesSync(bytes2);
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
