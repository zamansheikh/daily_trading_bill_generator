import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:daily_trading_bill_generator/core/catalog/product_matcher.dart';
import 'package:daily_trading_bill_generator/core/catalog/seed_catalog.dart';
import 'package:daily_trading_bill_generator/core/memo/memo_builder.dart';
import 'package:daily_trading_bill_generator/core/ordersheet/order_sheet_xlsx.dart';
import 'package:daily_trading_bill_generator/core/parsing/po_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('order sheet for the 63 warehouse POs matches the reference layout', () {
    final catalog = SeedCatalog.build();
    final matcher = ProductMatcher(catalog);
    const f = 'sample_pdf/inputs/BARISHAL-2_merged.pdf';
    final orders = PoParser().parseBytes(File(f).readAsBytesSync(), sourceFile: f).orders;
    for (final o in orders) {
      for (final it in o.items) {
        it.productId = matcher.match(o.chain, it).product?.id;
      }
    }
    final columns = [for (final o in orders) OrderSheetColumn(po: o, outletDisplayName: defaultOutletDisplayName(o.outletName, note: o.note))];
    expect(columns.firstWhere((c) => c.po.poNumber == 'PO-3800-01-26-053551').label, 'Barishal-2');
    expect(columns.map((c) => c.label), contains('Cox’s-Bazar-2'));
    expect(columns.map((c) => c.label), contains('Board-Bazar-Gazipur'));

    final bytes = OrderSheetXlsx(catalog).build(sortAlphabetically(columns), title: 'Order sheet SEP-2 (DLCL)');
    Directory('build/test_memos').createSync(recursive: true);
    File('build/test_memos/Order sheet SEP-2 (DLCL).xlsx').writeAsBytesSync(bytes);

    final zip = ZipDecoder().decodeBytes(bytes);
    String read(String name) => utf8.decode(zip.findFile(name)!.content as List<int>);
    final shared = read('xl/sharedStrings.xml');
    final sheet = read('xl/worksheets/sheet1.xml');
    for (final s in ['PO Number', 'Item', 'WT', 'TP', 'MRP', 'Barishal 2', 'Chattogram Halishahar Bashundhara', 'Sheet 1 TOTAL', 'Sheet 6 TOTAL', 'Grand Total', 'Total KG', 'জইন', 'PO- 3800- 01- 26- 053551']) {
      expect(shared, contains(s), reason: s);
    }
    // Ajwain, first product row: grand total 150 pieces = 7.5 kg, as on the reference sheet.
    final ajwainRow = RegExp(r'<row [^>]*r="3"[^>]*>(.*?)</row>', dotAll: true).firstMatch(sheet)!.group(1)!;
    expect(ajwainRow, contains('<v>150.0</v>'));
    expect(ajwainRow, contains('<v>7.5</v>'));
    // The per-PO amount row reproduces each PO total (first PO: 3,603.90).
    expect(sheet, contains('SUMPRODUCT('));
    expect(sheet, contains('<v>3603.9</v>'));
    expect(sheet, isNot(contains('missing formula')));
    // Long Bangla names wrap: "কালো গোলমরিচ গুড়া" (Ground Black pepper) gets a two-line row.
    final st = read('xl/styles.xml');
    expect(st, contains('wrapText="1"'));
    final rowGbp = RegExp(r'<row [^>]*r="41"[^>]*>').firstMatch(sheet)!.group(0)!;
    expect(rowGbp, contains('ht="25.5"'), reason: 'row 41 = Ground Black pepper, 2 lines x 17 px = 25.5 pt');
    // Rotated outlet header row is tall enough for the longest label.
    final row2 = RegExp(r'<row [^>]*r="2"[^>]*>').firstMatch(sheet)!.group(0)!;
    final ht2 = double.parse(RegExp(r'ht="([\d.]+)"').firstMatch(row2)!.group(1)!);
    expect(ht2, greaterThan(40));
  });

  test('Best Buy final quantity sheet matches the reference values', () {
    final catalog = SeedCatalog.build();
    final matcher = ProductMatcher(catalog);
    const f = 'sample_pdf/inputs/Daily Trading PO DSD 16.09.26.pdf';
    final orders = PoParser().parseBytes(File(f).readAsBytesSync(), sourceFile: f).orders;
    for (final o in orders) {
      for (final it in o.items) {
        it.productId = matcher.match(o.chain, it).product?.id;
      }
    }
    final columns = sortAlphabetically([for (final o in orders) OrderSheetColumn(po: o, outletDisplayName: defaultOutletDisplayName(o.outletName, note: o.note))]);
    final bytes = OrderSheetXlsx(catalog).build(columns, title: 'Final quantity sheet SEP 2');
    File('build/test_memos/Final quantity sheet SEP 2.xlsx').writeAsBytesSync(bytes);
    final zip = ZipDecoder().decodeBytes(bytes);
    String read(String name) => utf8.decode(zip.findFile(name)!.content as List<int>);
    final shared = read('xl/sharedStrings.xml');
    final sheet = read('xl/worksheets/sheet1.xml');
    for (final s in ['Item', 'WT', 'TP', 'MRP', 'BBUY Aftabnagor Bot Tola', 'BBUY Mogbazar Wireless Gate', 'Total 1', 'Grand Total', 'Total KG', 'কাঠবাদাম']) {
      expect(shared, contains(s), reason: s);
    }
    expect(shared, isNot(contains('PO Number')));
    expect(shared, isNot(contains('Amount Tk.')));
    // Row 3 = Almond 100gm: 12 + 12 pieces = 24, 100 g each = 2.4 kg, as on the reference sheet.
    final almond = RegExp(r'<row [^>]*r="3"[^>]*>(.*?)</row>', dotAll: true).firstMatch(sheet)!.group(1)!;
    expect(almond, contains('<v>100.0</v>'));
    expect(almond, contains('<v>24.0</v>'));
    expect(almond, contains('<v>2.4</v>'));
    expect(almond, contains('/1000'));
  });
}
