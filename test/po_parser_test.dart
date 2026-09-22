import 'dart:io';

import 'package:daily_trading_bill_generator/core/parsing/po_parser.dart';
import 'package:daily_trading_bill_generator/domain/chain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = PoParser();

  test('Best Buy PO file: 5 orders, all totals verified', () {
    const f = 'sample_pdf/inputs/Daily Trading PO DSD 16.09.26.pdf';
    final r = parser.parseBytes(File(f).readAsBytesSync(), sourceFile: f);
    expect(r.orders.length, 5);
    for (final o in r.orders) {
      expect(o.chain, Chain.bestBuy, reason: o.poNumber);
      expect(o.totalsMatch, isTrue, reason: '${o.poNumber}: ${o.warnings}');
      expect(o.warnings, isEmpty, reason: o.poNumber);
      expect(o.poDate, '16-Sep-2026');
      expect(o.purchaser, 'DS Selim Reza Mithun');
      expect(o.note, 'DSD');
    }
    final first = r.orders.first;
    expect(first.poNumber, 'PO-12000-01-26-011528');
    expect(first.outletName, 'BBUY-Aftabnagor-Bot Tola');
    expect(first.address, contains('Aftabnagar'));
    expect(first.items.length, 15);
    expect(first.items[3].name, 'Daily Shopping Caraway Seeds (Shahi Jeera) 25gm');
    expect(first.items[3].quantity, 18);
    expect(first.items[3].total, 777.60);
    expect(first.declaredTotal, 30433.20);
    final last = r.orders.last;
    expect(last.poNumber, 'PO-12000-01-26-011532');
    expect(last.outletName, 'BBUY-Mogbazar-Wireless Gate');
    expect(last.items.length, 21);
    expect(last.declaredTotal, 25158.60);
  });

  test('Daily Shopping PO file: 51 orders incl. multi-page ones, all verified', () {
    const f = 'sample_pdf/inputs/DT PO (2).pdf';
    final sw = Stopwatch()..start();
    final r = parser.parseBytes(File(f).readAsBytesSync(), sourceFile: f);
    // ignore: avoid_print
    print('parsed ${r.orders.length} orders from ${r.pageCount} pages in ${sw.elapsedMilliseconds}ms');
    expect(r.pageCount, 71);
    expect(r.orders.length, 51);
    expect(r.orders.map((o) => o.poNumber).toSet().length, 51);
    for (final o in r.orders) {
      expect(o.chain, Chain.dailyShopping, reason: o.poNumber);
      expect(o.totalsMatch, isTrue, reason: '${o.poNumber}: ${o.warnings}');
      expect(o.warnings, isEmpty, reason: '${o.poNumber}: ${o.warnings}');
      expect(o.outletName, startsWith('Daily Shopping'));
      expect(o.note, 'PO');
      for (final it in o.items) {
        expect(it.code.length, 10, reason: '${o.poNumber} ${it.name}');
        expect(it.shelfPrice, isNotNull);
      }
    }
    final first = r.orders.first;
    expect(first.poNumber, 'PO-3800-01-26-050614');
    expect(first.pages, [1, 2]);
    expect(first.items.length, 29);
    expect(first.items[6].name, 'Daily Shopping Chines Papor 200gm');
    expect(first.items[18].code, '3000000568');
    expect(first.items[18].name, 'Daily Shopping Isobgul Bhushi(Bran) 50gm');
    expect(first.declaredTotal, 29610.90);
    final multi = r.orders.where((o) => o.pages.length > 1).toList();
    expect(multi.length, greaterThanOrEqualTo(5));
  });
}
