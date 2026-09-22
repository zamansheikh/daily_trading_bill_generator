import 'dart:io';

import 'package:daily_trading_bill_generator/app/state/app_state.dart';
import 'package:daily_trading_bill_generator/core/memo/memo_builder.dart';
import 'package:daily_trading_bill_generator/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a removed line leaves the memo, totals still reconcile, and it can be restored', () async {
    final dir = Directory.systemTemp.createTempSync('dtbg_rm');
    final db = await AppDatabase.open(path: p.join(dir.path, 'app.db'));
    final state = AppState(db: db, bannerBytes: File('assets/images/memo_banner.png').readAsBytesSync());
    await state.init();
    try {
      await state.importFiles(['sample_pdf/inputs/Daily Trading PO DSD 16.09.26.pdf']);
      final o = state.orders.first;
      final before = o.po.items.length;
      final declared = o.po.declaredTotal!;
      final removed = o.po.items[3]; // Caraway Seeds
      expect(removed.cleanName, startsWith('Caraway'));

      await state.removeItem(o, 3);
      expect(o.po.items.length, before - 1);
      expect(o.matchKinds.length, before - 1);
      expect(o.po.removedItems.single.code, removed.code);
      expect(o.po.computedTotal, closeTo(declared - removed.total, 0.001));
      expect(o.po.totalsMatch, isTrue, reason: 'removed lines still reconcile against the PO total');
      expect(o.isClean, isTrue);

      final memo = MemoBuilder(state.catalog).build(o.po, memoNumber: 1, supplyDate: DateTime(2026, 9, 22), outletDisplayName: 'x');
      expect(memo.rows.where((r) => r.nameEn == 'Caraway Seeds').single.quantity, isNull);
      expect(memo.total, closeTo(declared - removed.total, 0.001));

      // Survives a reload from the database.
      final stored = await db.getOrder(o.po.poNumber);
      expect(stored!.po.removedItems.length, 1);
      expect(stored.po.items.length, before - 1);

      await state.restoreItem(o, o.po.removedItems.single);
      expect(o.po.items.length, before);
      expect(o.po.items[3].code, removed.code, reason: 'restored in serial order');
      expect(o.matchKinds.length, before);
      expect(o.po.removedItems, isEmpty);
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
}
