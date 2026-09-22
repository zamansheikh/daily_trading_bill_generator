import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../../domain/chain.dart';
import '../../domain/models.dart';
import '../catalog/catalog.dart';
import '../catalog/product_matcher.dart';
import '../memo/memo_builder.dart';

/// One column of the order sheet: a purchase order for one outlet.
class OrderSheetColumn {
  OrderSheetColumn({required this.po, required this.outletDisplayName});
  final PurchaseOrder po;
  final String outletDisplayName;

  /// Short outlet label as on the reference sheet: "BARISHAL-2" -> "Barishal-2",
  /// "COX'S BAZAR (BURMESE MARKET)" -> "Cox's-Bazar-(burmese-Market)".
  String get label {
    final raw = noteIsDestination(po.outletName, po.note)
        ? po.note
        : outletDisplayName.replaceFirst(RegExp(r'^Daily Shopping\s*-?\s*', caseSensitive: false), '');
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join('-');
  }
}

/// Builds the consolidated order sheet: products down the side, one column
/// per purchase order, quantities in the grid, a subtotal column after every
/// [outletsPerBlock] outlets, a grand total, total weight in kg, and the
/// amount of every PO along the bottom (SUMPRODUCT of trade price x qty).
class OrderSheetXlsx {
  OrderSheetXlsx(this.catalog, {this.outletsPerBlock = 11});
  final Catalog catalog;
  final int outletsPerBlock;

  static const _latin = 'Arial';
  static const _bangla = 'Nirmala UI';
  static const _headFill = '#D9D9D9';
  static const _totalFill = '#FFF2CC';

  List<int> build(List<OrderSheetColumn> columns, {required String title}) {
    final sorted = [...columns]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final chain = sorted.isEmpty || sorted.first.po.chain == Chain.unknown ? Chain.dailyShopping : sorted.first.po.chain;

    // Product rows: the chain's catalogue in print order, plus anything
    // ordered that is not in it.
    final rows = <_Row>[];
    final rowByProduct = <int, _Row>{};
    final rowByCode = <String, _Row>{};
    for (final p in catalog.productsFor(chain)) {
      final r = _Row(code: p.dtCode, name: p.nameEn, bangla: p.nameBn, size: p.size, tradePrice: catalog.price(chain, p.id));
      rows.add(r);
      rowByProduct[p.id] = r;
    }
    for (final c in sorted) {
      for (final it in c.po.items) {
        _Row? r = it.productId == null ? null : rowByProduct[it.productId!];
        if (r == null) {
          final p = catalog.byId(it.productId);
          if (p != null) {
            r = _Row(code: p.dtCode, name: p.nameEn, bangla: p.nameBn, size: p.size, tradePrice: catalog.price(chain, p.id));
            rows.add(r);
            rowByProduct[p.id] = r;
          } else {
            r = rowByCode[it.code];
            if (r == null) {
              r = _Row(code: it.code, name: it.cleanName, bangla: '', size: ProductMatcher.extractSize(it.name), tradePrice: it.rate);
              rows.add(r);
              rowByCode[it.code] = r;
            }
          }
        }
        r.tradePrice = it.rate; // the newest PO rate wins
        r.mrp ??= it.shelfPrice;
        r.qty[c] = (r.qty[c] ?? 0) + it.quantity;
      }
    }

    final wb = Workbook();
    final ws = wb.worksheets[0];
    ws.name = 'Order sheet';

    // Layout: A code, B name, C Bangla, D WT, E TP, F MRP, then outlet blocks
    // with a total column after each, then Grand Total and Total KG.
    const firstOutletCol = 7;
    final blockCount = sorted.isEmpty ? 0 : ((sorted.length - 1) ~/ outletsPerBlock) + 1;
    final colOf = <OrderSheetColumn, int>{};
    final blockTotalCols = <int>[];
    var col = firstOutletCol;
    for (var b = 0; b < blockCount; b++) {
      final start = b * outletsPerBlock;
      final end = (start + outletsPerBlock).clamp(0, sorted.length);
      for (var i = start; i < end; i++) {
        colOf[sorted[i]] = col++;
      }
      blockTotalCols.add(col++);
    }
    final grandCol = col;
    final kgCol = col + 1;
    final lastCol = kgCol;

    const headerRow1 = 1, headerRow2 = 2, firstDataRow = 3;
    final lastDataRow = firstDataRow + rows.length - 1;
    final amountRow = lastDataRow + 1;

    // Widths.
    ws.getRangeByIndex(1, 1).columnWidth = 11;
    ws.getRangeByIndex(1, 2).columnWidth = 13;
    ws.getRangeByIndex(1, 3).columnWidth = 13;
    ws.getRangeByIndex(1, 4).columnWidth = 6.5;
    ws.getRangeByIndex(1, 5).columnWidth = 7;
    ws.getRangeByIndex(1, 6).columnWidth = 6.5;
    for (var c = firstOutletCol; c <= lastCol; c++) {
      ws.getRangeByIndex(1, c).columnWidth = blockTotalCols.contains(c) || c >= grandCol ? 7.5 : 6.2;
    }

    // Header rows.
    ws.setRowHeightInPixels(headerRow1, 18);
    ws.setRowHeightInPixels(headerRow2, 96);
    _head(ws.getRangeByIndex(headerRow1, 1), 'PO Number');
    _head(ws.getRangeByIndex(headerRow1, 2), title);
    _head(ws.getRangeByIndex(headerRow2, 1), 'Code');
    _head(ws.getRangeByIndex(headerRow2, 2), 'Name');
    _head(ws.getRangeByIndex(headerRow2, 3), 'Item');
    _head(ws.getRangeByIndex(headerRow2, 4), 'WT');
    _head(ws.getRangeByIndex(headerRow2, 5), 'TP');
    _head(ws.getRangeByIndex(headerRow2, 6), 'MRP');
    for (final c in sorted) {
      final x = colOf[c]!;
      _head(ws.getRangeByIndex(headerRow1, x), c.po.poNumber, size: 6, rotate: true);
      _head(ws.getRangeByIndex(headerRow2, x), c.label, rotate: true);
    }
    for (var b = 0; b < blockTotalCols.length; b++) {
      final x = blockTotalCols[b];
      _head(ws.getRangeByIndex(headerRow1, x), '${b * outletsPerBlock + 1}-${((b + 1) * outletsPerBlock).clamp(0, sorted.length)}', fill: _totalFill);
      _head(ws.getRangeByIndex(headerRow2, x), 'Sheet-${b + 1}-TOTAL', rotate: true, fill: _totalFill);
    }
    _head(ws.getRangeByIndex(headerRow1, grandCol), '', fill: _totalFill);
    _head(ws.getRangeByIndex(headerRow2, grandCol), 'Grand Total', rotate: true, fill: _totalFill);
    _head(ws.getRangeByIndex(headerRow1, kgCol), '', fill: _totalFill);
    _head(ws.getRangeByIndex(headerRow2, kgCol), 'Total KG', rotate: true, fill: _totalFill);

    // Product rows.
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final y = firstDataRow + i;
      ws.setRowHeightInPixels(y, 17);
      _text(ws.getRangeByIndex(y, 1), r.code, size: 7);
      _text(ws.getRangeByIndex(y, 2), r.name, size: 7);
      _text(ws.getRangeByIndex(y, 3), r.bangla, size: 8, font: _bangla);
      _text(ws.getRangeByIndex(y, 4), r.size, size: 7, center: true);
      _num(ws.getRangeByIndex(y, 5), r.tradePrice, format: '0.00');
      _num(ws.getRangeByIndex(y, 6), r.mrp, format: '0.##');
      var grand = 0.0;
      for (var b = 0; b < blockCount; b++) {
        final start = b * outletsPerBlock;
        final end = (start + outletsPerBlock).clamp(0, sorted.length);
        var blockSum = 0.0;
        for (var k = start; k < end; k++) {
          final c = sorted[k];
          final q = r.qty[c];
          _num(ws.getRangeByIndex(y, colOf[c]!), q, format: '0.##');
          blockSum += q ?? 0;
        }
        final firstX = _colName(colOf[sorted[start]]!);
        final lastX = _colName(colOf[sorted[end - 1]]!);
        final tcell = ws.getRangeByIndex(y, blockTotalCols[b]);
        tcell.setFormula('=SUM($firstX$y:$lastX$y)');
        tcell.setFormulaNumberValue(blockSum);
        _style(tcell, size: 8, bold: true, fill: _totalFill, format: '0.##');
        grand += blockSum;
      }
      final gcell = ws.getRangeByIndex(y, grandCol);
      if (blockTotalCols.isEmpty) {
        gcell.setNumber(0);
      } else {
        gcell.setFormula('=${blockTotalCols.map((x) => '${_colName(x)}$y').join('+')}');
        gcell.setFormulaNumberValue(grand);
      }
      _style(gcell, size: 8, bold: true, fill: _totalFill, format: '0.##');
      final kg = _kg(r.size);
      final kcell = ws.getRangeByIndex(y, kgCol);
      if (kg != null) {
        kcell.setFormula('=ROUND(${_colName(grandCol)}$y*$kg,3)');
        kcell.setFormulaNumberValue(_round3(grand * kg));
      }
      _style(kcell, size: 8, fill: _totalFill, format: '0.##');
    }

    // Amount row: value of each PO = SUMPRODUCT(TP, qty), which equals the PO total.
    _head(ws.getRangeByIndex(amountRow, 3), 'Amount Tk.');
    for (var c = 1; c <= 6; c++) {
      if (c != 3) _head(ws.getRangeByIndex(amountRow, c), '');
    }
    for (final c in sorted) {
      final x = colOf[c]!;
      final xn = _colName(x);
      final cell = ws.getRangeByIndex(amountRow, x);
      cell.setFormula('=ROUND(SUMPRODUCT(\$E$firstDataRow:\$E$lastDataRow,$xn$firstDataRow:$xn$lastDataRow),2)');
      cell.setFormulaNumberValue(_round2(c.po.computedTotal));
      _style(cell, size: 7, bold: true, fill: _headFill, format: '#,##0.00');
      cell.cellStyle.rotation = 90;
    }
    for (var b = 0; b < blockTotalCols.length; b++) {
      final start = b * outletsPerBlock;
      final end = (start + outletsPerBlock).clamp(0, sorted.length);
      final firstX = _colName(colOf[sorted[start]]!);
      final lastX = _colName(colOf[sorted[end - 1]]!);
      final cell = ws.getRangeByIndex(amountRow, blockTotalCols[b]);
      cell.setFormula('=ROUND(SUM($firstX$amountRow:$lastX$amountRow),2)');
      cell.setFormulaNumberValue(_round2(sorted.sublist(start, end).fold(0.0, (s, c) => s + c.po.computedTotal)));
      _style(cell, size: 7, bold: true, fill: _totalFill, format: '#,##0.00');
      cell.cellStyle.rotation = 90;
    }
    final gAmount = ws.getRangeByIndex(amountRow, grandCol);
    if (blockTotalCols.isNotEmpty) {
      gAmount.setFormula('=${blockTotalCols.map((x) => '${_colName(x)}$amountRow').join('+')}');
      gAmount.setFormulaNumberValue(_round2(sorted.fold(0.0, (s, c) => s + c.po.computedTotal)));
    }
    _style(gAmount, size: 7, bold: true, fill: _totalFill, format: '#,##0.00');
    gAmount.cellStyle.rotation = 90;
    ws.setRowHeightInPixels(amountRow, 64);

    // Borders over the whole grid.
    final all = ws.getRangeByIndex(headerRow1, 1, amountRow, lastCol);
    all.cellStyle.borders.all.lineStyle = LineStyle.thin;
    all.cellStyle.borders.all.color = '#808080';

    // Code and English name stay in the file but hidden, as on the reference
    // sheet; the printed sheet shows the Bangla item name.
    ws.getRangeByIndex(1, 1, 1, 2).showColumns(false);

    // Freeze the product columns and header rows; repeat them on every page.
    ws.getRangeByIndex(firstDataRow, firstOutletCol).freezePanes();
    final ps = ws.pageSetup;
    ps.paperSize = ExcelPaperSize.paperA4;
    ps.orientation = ExcelPageOrientation.portrait;
    ps.isFitToPage = true;
    // The library only writes <pageSetup> (and with it the A4 paper size)
    // when something differs from its defaults; 300 dpi is a harmless trigger.
    ps.printQuality = 300;
    ps.fitToPagesWide = blockCount == 0 ? 1 : blockCount;
    ps.fitToPagesTall = 1;
    // Repeat the item columns on every printed page (the library derives the
    // column span from a cell range). Rows need no repeat: one page tall.
    ps.printTitleColumns = 'C1:F1';
    ps.leftMargin = 0.25;
    ps.rightMargin = 0.25;
    ps.topMargin = 0.25;
    ps.bottomMargin = 0.25;
    ps.printArea = 'A1:${_colName(lastCol)}$amountRow';

    final bytes = wb.saveAsStream();
    wb.dispose();
    return bytes;
  }

  void _head(Range r, String text, {double size = 7.5, bool rotate = false, String fill = _headFill}) {
    r.setText(text);
    r.cellStyle
      ..fontName = _latin
      ..fontSize = size
      ..bold = true
      ..backColor = fill
      ..hAlign = HAlignType.center
      ..vAlign = VAlignType.center
      ..wrapText = !rotate;
    if (rotate) r.cellStyle.rotation = 90;
  }

  void _text(Range r, String text, {double size = 8, String font = _latin, bool center = false}) {
    r.setText(text);
    r.cellStyle
      ..fontName = font
      ..fontSize = size
      ..hAlign = center ? HAlignType.center : HAlignType.left
      ..vAlign = VAlignType.center;
  }

  void _num(Range r, double? v, {required String format}) {
    if (v != null) r.setNumber(v);
    _style(r, size: 8, format: format);
  }

  void _style(Range r, {required double size, bool bold = false, String? fill, required String format}) {
    r.numberFormat = format;
    r.cellStyle
      ..fontName = _latin
      ..fontSize = size
      ..bold = bold
      ..hAlign = HAlignType.center
      ..vAlign = VAlignType.center;
    if (fill != null) r.cellStyle.backColor = fill;
  }

  /// Weight of one unit in kg from its size text ("100gm" -> 0.1, "1KG" -> 1).
  static double? _kg(String size) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|gm|g)\b', caseSensitive: false).firstMatch(size);
    if (m == null) return null;
    final v = double.parse(m.group(1)!);
    return m.group(2)!.toLowerCase() == 'kg' ? v : v / 1000;
  }

  static String _colName(int index) {
    var n = index;
    final sb = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      sb.write(String.fromCharCode(65 + rem));
      n = (n - 1) ~/ 26;
    }
    return sb.toString().split('').reversed.join();
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
  static double _round3(double v) => (v * 1000).roundToDouble() / 1000;
}

class _Row {
  _Row({required this.code, required this.name, required this.bangla, required this.size, this.tradePrice});
  final String code;
  final String name;
  final String bangla;
  final String size;
  double? tradePrice;
  double? mrp;
  final Map<OrderSheetColumn, double> qty = {};
}
