import 'dart:io';

import 'package:daily_trading_bill_generator/app/app.dart';
import 'package:daily_trading_bill_generator/app/state/app_state.dart';
import 'package:daily_trading_bill_generator/data/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Renders every screen at phone and desktop sizes with real imported
/// orders. Any RenderFlex overflow or build error fails the test.
void main() {
  late Directory dir;
  late AppDatabase db;
  late AppState state;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('dtbg_ui');
    db = await AppDatabase.open(path: p.join(dir.path, 'ui.db'));
    state = AppState(db: db, bannerBytes: File('assets/images/memo_banner.png').readAsBytesSync());
    await state.init();
    await state.setOutputDir(p.join(dir.path, 'out'));
    await state.importFiles(['sample_pdf/inputs/Daily Trading PO DSD 16.09.26.pdf']);
    await state.generateMemos([state.orders.first]);
  });

  tearDownAll(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> walk(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(DailyTradingApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Purchase orders'), findsOneWidget);
    expect(find.textContaining('BBUY'), findsWidgets);
    expect(tester.takeException(), isNull);

    // PO detail (with items table or cards) and back.
    await tester.tap(find.textContaining('Aftabnagor').first);
    await tester.pumpAndSettle();
    expect(find.text('Items'), findsOneWidget);
    expect(find.textContaining('Almond'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Other tabs.
    for (final tab in ['History', 'Catalogue', 'Settings']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    expect(find.text('Next memo number'), findsOneWidget);
    // Developer credit sits at the bottom of the settings list.
    await tester.scrollUntilVisible(find.text('github.com/zamansheikh'), 300, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    expect(find.text('fb.com/zamansheikh.404'), findsOneWidget);
    expect(find.text('Restore shipped catalogue'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Catalogue edit dialog.
    await tester.tap(find.text('Catalogue').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ajwain').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit product'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  }

  testWidgets('phone layout renders without overflow', (tester) => walk(tester, const Size(390, 844)));
  testWidgets('tablet layout renders without overflow', (tester) => walk(tester, const Size(820, 1180)));
  testWidgets('desktop layout renders without overflow', (tester) => walk(tester, const Size(1440, 900)));
}
