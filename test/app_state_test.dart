import 'dart:io';

import 'package:daily_trading_bill_generator/app/state/app_state.dart';
import 'package:daily_trading_bill_generator/data/app_database.dart';
import 'package:daily_trading_bill_generator/domain/chain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('end to end: import both sample files, generate memos, files land on disk', () async {
    final dir = Directory.systemTemp.createTempSync('dtbg_e2e');
    final db = await AppDatabase.open(path: p.join(dir.path, 'app.db'));
    final state = AppState(db: db, bannerBytes: File('assets/images/memo_banner.png').readAsBytesSync());
    await state.init();
    try {
      await state.setNextMemoNumber(9809);
      await state.setOutputDir(p.join(dir.path, 'out'));
      state.setSupplyDate(DateTime(2026, 9, 22));

      final summary = await state.importFiles([
        'sample_pdf/inputs/Daily Trading PO DSD 16.09.26.pdf',
        'sample_pdf/inputs/DT PO (2).pdf',
      ]);
      expect(summary.orders, 56);
      expect(summary.errors, isEmpty);
      expect(state.orders.length, 56);
      expect(state.orders.where((o) => o.hasUnmatched), isEmpty);
      expect(state.orders.where((o) => !o.isClean), isEmpty);

      final bb = state.orders.firstWhere((o) => o.po.poNumber == 'PO-12000-01-26-011532');
      expect(bb.outletDisplayName, 'BBUY Mogbazar Wireless Gate');
      await state.setOutletDisplayName(bb, 'BBUY Grocery Mogbazar Wireless Gate');
      final ds = state.orders.firstWhere((o) => o.po.chain == Chain.dailyShopping);

      final result = await state.generateMemos([bb, ds]);
      expect(result.errors, isEmpty);
      expect(result.generated.length, 2);
      expect(bb.memoNumber, 9809);
      expect(ds.memoNumber, 9810);
      expect(p.basename(bb.memoPath!), '9809(BBUY Grocery Mogbazar Wireless Gate).pdf');
      expect(File(bb.memoPath!).lengthSync(), greaterThan(10000));
      expect(File(ds.memoPath!).existsSync(), isTrue);
      expect(result.outputDir, endsWith('2026-09-22'));
      expect(state.nextMemoNumber, 9811);
      expect(state.history.length, 2);

      // Regenerating keeps the memo number; prices were learned from the PO.
      final again = await state.generateMemos([bb]);
      expect(again.generated.single.memoNumber, 9809);
      expect(state.nextMemoNumber, 9811);
      final almond100 = state.catalog.byDtCode('5000000561')!;
      expect(state.catalog.price(Chain.bestBuy, almond100.id), 213.20);

      // Order sheet: the user's outlet sequence is remembered and applied.
      final all = state.orders.toList();
      final alpha = state.orderSheetColumns(all).map((c) => c.label).toList();
      expect(alpha, equals([...alpha]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))), reason: 'alphabetical when nothing is remembered');
      final custom = [...alpha.reversed];
      await state.saveOutletOrder(custom);
      expect(state.orderSheetColumns(all).map((c) => c.label).toList(), custom);
      await state.setOutletsPerBlock(5);
      final sheetPath = await state.generateOrderSheet(state.orderSheetColumns(all), title: 'Order sheet test');
      expect(File(sheetPath).lengthSync(), greaterThan(5000));
      expect(p.basename(sheetPath), 'Order sheet test.xlsx');

      // The outlet name edit is remembered for the next import of that outlet.
      expect(await db.outletDisplayName('BBUY-Mogbazar-Wireless Gate'), 'BBUY Grocery Mogbazar Wireless Gate');
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
}
