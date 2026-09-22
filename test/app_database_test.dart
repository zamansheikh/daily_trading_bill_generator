import 'dart:io';

import 'package:daily_trading_bill_generator/core/parsing/po_parser.dart';
import 'package:daily_trading_bill_generator/data/app_database.dart';
import 'package:daily_trading_bill_generator/domain/chain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('database seeds, stores orders and hands out memo numbers', () async {
    final dir = Directory.systemTemp.createTempSync('dtbg_db');
    final db = await AppDatabase.open(path: p.join(dir.path, 'test.db'));
    try {
      final cat = await db.loadCatalog();
      expect(cat.products.length, 78);
      expect(cat.productsFor(Chain.bestBuy).length, 71);
      expect(cat.byBuyerCode(Chain.bestBuy, '895672')?.nameEn, 'Almond');
      expect(cat.price(Chain.dailyShopping, cat.byDtCode('5000000561')!.id), 179.40);

      expect(await db.takeMemoNumber(), 1);
      expect(await db.takeMemoNumber(), 2);
      await db.setSetting('next_memo_number', '9809');
      expect(await db.takeMemoNumber(), 9809);

      const f = 'sample_pdf/inputs/Daily Trading PO DSD 16.09.26.pdf';
      final po = PoParser().parseBytes(File(f).readAsBytesSync(), sourceFile: f).orders.first;
      await db.saveOrder(po, outletDisplayName: 'BBUY Aftabnagor Bot Tola');
      final stored = await db.getOrder(po.poNumber);
      expect(stored, isNotNull);
      expect(stored!.po.items.length, 15);
      expect(stored.outletDisplayName, 'BBUY Aftabnagor Bot Tola');
      expect(stored.memoNumber, isNull);

      await db.saveMemoResult(poNumber: po.poNumber, memoNumber: 9809, supplyDate: DateTime(2026, 9, 22), memoPath: '/tmp/x.pdf', outletDisplayName: 'X');
      expect((await db.listMemos()).single.memoNumber, 9809);
      // Re-importing the same PO keeps its memo number.
      await db.saveOrder(po, outletDisplayName: 'X');
      expect((await db.getOrder(po.poNumber))!.memoNumber, 9809);

      await db.savePrice(Chain.bestBuy, cat.byDtCode('5000000641')!.id, 40.0);
      await db.saveAlias(Chain.bestBuy, '999999', cat.byDtCode('5000000641')!.id);
      final cat2 = await db.loadCatalog();
      expect(cat2.price(Chain.bestBuy, cat2.byDtCode('5000000641')!.id), 40.0);
      expect(cat2.byBuyerCode(Chain.bestBuy, '999999')?.nameEn, 'Ajwain');
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
}
