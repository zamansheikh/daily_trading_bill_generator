import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:daily_trading_bill_generator/core/catalog/product_matcher.dart';
import 'package:daily_trading_bill_generator/core/catalog/seed_catalog.dart';
import 'package:daily_trading_bill_generator/core/memo/memo_builder.dart';
import 'package:daily_trading_bill_generator/core/memo/memo_xlsx.dart';
import 'package:daily_trading_bill_generator/core/parsing/po_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Excel memo carries the same data as the PDF, with live formulas', () {
    final catalog = SeedCatalog.build();
    final matcher = ProductMatcher(catalog);
    const f = 'sample_pdf/inputs/Daily Trading PO DSD 16.09.26.pdf';
    final po = PoParser().parseBytes(File(f).readAsBytesSync(), sourceFile: f).orders.last;
    for (final it in po.items) {
      it.productId = matcher.match(po.chain, it).product?.id;
    }
    final doc = MemoBuilder(catalog).build(po, memoNumber: 9808, supplyDate: DateTime(2026, 9, 19), outletDisplayName: 'BBUY Grocery Mogbazar Wireless Gate');
    final banner = File('assets/images/memo_banner.png').readAsBytesSync();
    final bytes = MemoXlsx(bannerImage: banner).build(doc);
    Directory('build/test_memos').createSync(recursive: true);
    File('build/test_memos/9808(BBUY Grocery Mogbazar Wireless Gate).xlsx').writeAsBytesSync(bytes);

    final zip = ZipDecoder().decodeBytes(bytes);
    String read(String name) => utf8.decode(zip.findFile(name)!.content as List<int>);
    final shared = read('xl/sharedStrings.xml');
    final sheet = read('xl/worksheets/sheet1.xml');
    expect(shared, contains('9808'));
    expect(shared, contains('PO-12000-01-26-011532'));
    expect(shared, contains('BBUY Grocery Mogbazar Wireless Gate'));
    expect(shared, contains('Almond'));
    expect(shared, contains('কাঠবাদাম'));
    expect(shared, contains('১'));
    expect(sheet, contains('ROUND(SUM(H9:H44)+SUM(P9:P44),2)'));
    expect(sheet, contains('ROUND(F10*G10,2)'));
    // Formula cells are numeric with exact cached results (Almond 100gm: 12 x 213.20).
    final h8 = RegExp(r'<c r="H10"[^>]*>.*?</c>').firstMatch(sheet)!.group(0)!;
    expect(h8, isNot(contains('t="str"'))); // no type attribute = numeric cell
    expect(h8, contains('<v>2558.4</v>'));
    expect(h8, isNot(contains('3999')));
    final p43 = RegExp(r'<c r="P45"[^>]*>.*?</c>').firstMatch(sheet)!.group(0)!;
    expect(p43, contains('<v>25158.6</v>'));
    expect(sheet, isNot(contains('missing formula')));
    // Ajwain (row 9, not ordered) is a plain 0, not a formula over empty cells.
    final h7 = RegExp(r'<c r="H9"[^>]*>.*?</c>').firstMatch(sheet)!.group(0)!;
    expect(h7, isNot(contains('<f>')));
    expect(h7, contains('<v>0.0</v>'));
    // Labels sit in the top-left cell of their merged ranges.
    expect(shared, contains('Memo No.'));
    expect(shared, contains('Order date:'));
    expect(shared, contains('Supply Date:'));
    expect(shared, contains('Name/address:'));
    expect(shared, contains('Amount in Total'));

    // User's sizes: data rows 16.5 pt, displayed widths SL 1.14, English name
    // 12.71, Bangla name 8.57, Size 4.14, Amount 6.29 (Excel stores +0.71).
    for (final r in [9, 44]) {
      expect(RegExp('<row [^>]*r="$r"[^>]*>').firstMatch(sheet)!.group(0), contains('ht="16.5"'), reason: 'row $r');
    }
    double width(int col) => double.parse(RegExp('<col min="$col" max="$col" width="([\\d.]+)"').firstMatch(sheet)!.group(1)!);
    expect(width(1), closeTo(1.14 + 0.714, 0.01));
    expect(width(3), closeTo(12.71 + 0.714, 0.01));
    expect(width(4), closeTo(8.57 + 0.714, 0.01));
    expect(width(5), closeTo(4.14 + 0.714, 0.01));
    expect(width(8), closeTo(6.29 + 0.714, 0.01));
    // One font everywhere: Kalpurush 7.
    final st = read('xl/styles.xml');
    final sizes = RegExp(r'<sz val="([\d.]+)"').allMatches(st).map((m) => m.group(1)).toSet();
    final names = RegExp(r'<name val="([^"]+)"').allMatches(st).map((m) => m.group(1)).toSet();
    expect(sizes.difference({'11', '11.0', '7', '7.0'}), isEmpty, reason: 'only the default 11 and 7: $sizes');
    expect(names.difference({'Calibri', 'Kalpurush'}), isEmpty, reason: '$names');
    // Quantities use General, so 12 never shows as "12.".
    expect(st, isNot(contains('formatCode="0.##"')));
    expect(zip.files.any((e) => e.name.startsWith('xl/media/')), isTrue, reason: 'banner image embedded');
    // 71 rows -> 36 per column -> rows 9..44.
    expect(sheet, contains('r="44"'));
  });
}
