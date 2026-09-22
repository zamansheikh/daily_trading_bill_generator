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

    final bytes = OrderSheetXlsx(catalog).build(columns, title: 'Order sheet SEP-2 (DLCL)');
    Directory('build/test_memos').createSync(recursive: true);
    File('build/test_memos/Order sheet SEP-2 (DLCL).xlsx').writeAsBytesSync(bytes);

    final zip = ZipDecoder().decodeBytes(bytes);
    String read(String name) => utf8.decode(zip.findFile(name)!.content as List<int>);
    final shared = read('xl/sharedStrings.xml');
    final sheet = read('xl/worksheets/sheet1.xml');
    for (final s in ['PO Number', 'Item', 'WT', 'TP', 'MRP', 'Barishal-2', 'Sheet-1-TOTAL', 'Sheet-6-TOTAL', 'Grand Total', 'Total KG', 'জইন', 'PO-3800-01-26-053551']) {
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
  });
}
