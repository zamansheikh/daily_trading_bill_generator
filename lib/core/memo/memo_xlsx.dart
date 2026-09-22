import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import 'bengali.dart';
import 'memo_builder.dart';

/// Writes a [MemoDocument] as an Excel workbook laid out like the memo PDF:
/// letterhead, black label cells, the catalogue split into two side-by-side
/// tables, a total line and signature lines. Amounts and the total are live
/// formulas, so quantities can be corrected in Excel and the sheet follows.
class MemoXlsx {
  MemoXlsx({required this.bannerImage});

  /// PNG/JPEG bytes of the letterhead banner.
  final Uint8List bannerImage;

  static const _black = '#000000';
  static const _white = '#FFFFFF';
  static const _grey = '#EDEDED';
  static const _latin = 'Arial';
  static const _bangla = 'Nirmala UI';

  /// Column widths (Excel character units) for one half of the table.
  static const List<double> _half = [3.2, 9.6, 13.0, 10.5, 5.6, 4.2, 6.8, 8.2];

  List<int> build(MemoDocument doc) {
    final wb = Workbook();
    final ws = wb.worksheets[0];
    ws.name = 'Memo';
    ws.showGridlines = false;

    for (var c = 0; c < 16; c++) {
      ws.getRangeByIndex(1, c + 1).columnWidth = _half[c % 8];
    }

    // Letterhead: rows 1-3, image centred over the full width.
    ws.getRangeByName('A1:P3').merge();
    ws.setRowHeightInPixels(1, 20);
    ws.setRowHeightInPixels(2, 20);
    ws.setRowHeightInPixels(3, 20);
    final pic = ws.pictures.addStream(1, 1, bannerImage);
    pic.width = 740;
    pic.height = 52;
    _box(ws.getRangeByName('A1:P3'));

    // Header block.
    ws.setRowHeightInPixels(4, 24);
    ws.setRowHeightInPixels(5, 24);
    _label(ws.getRangeByName('A4:B4'), 'Memo No.');
    _value(ws.getRangeByName('C4:E4'), doc.memoNumber.toString(), size: 11);
    _value(ws.getRangeByName('F4:K4'), doc.poNumber, size: 11);
    _label(ws.getRangeByName('L4:N4'), 'Order date:');
    _value(ws.getRangeByName('O4:P4'), doc.orderDate == null ? '' : _date(doc.orderDate!), size: 10);
    _label(ws.getRangeByName('A5:B5'), 'Name/address:', size: 8);
    _value(ws.getRangeByName('C5:K5'), doc.outletDisplayName, size: 10);
    _label(ws.getRangeByName('L5:N5'), 'Supply Date:');
    _value(ws.getRangeByName('O5:P5'), _date(doc.supplyDate), size: 11);

    // Table header.
    const headers = ['Sl.', 'Product Code', 'Product Name', 'Product Name', 'Size', 'Qty', 'Unit price', 'Amount Tk.'];
    ws.setRowHeightInPixels(6, 26);
    for (var c = 0; c < 16; c++) {
      final r = ws.getRangeByIndex(6, c + 1);
      r.setText(headers[c % 8]);
      final s = r.cellStyle;
      s.backColor = _black;
      s.fontColor = _white;
      s.bold = true;
      s.fontName = _latin;
      s.fontSize = 7;
      s.hAlign = HAlignType.center;
      s.vAlign = VAlignType.center;
      s.wrapText = true;
      _thin(r);
    }

    // Rows.
    final rowsPerColumn = (doc.rows.length + 1) ~/ 2;
    const firstRow = 7;
    for (var i = 0; i < rowsPerColumn; i++) {
      final excelRow = firstRow + i;
      ws.setRowHeightInPixels(excelRow, 19);
      final shaded = i.isOdd;
      _memoRow(ws, excelRow, 1, doc.rows[i], shaded);
      final j = i + rowsPerColumn;
      _memoRow(ws, excelRow, 9, j < doc.rows.length ? doc.rows[j] : null, shaded);
    }
    final lastRow = firstRow + rowsPerColumn - 1;

    // Total line: the sum of both amount columns.
    final totalRow = lastRow + 1;
    ws.setRowHeightInPixels(totalRow, 22);
    final totalLabel = ws.getRangeByIndex(totalRow, 1, totalRow, 15);
    totalLabel.merge();
    _eachCell(totalLabel, (c) {
      c.cellStyle
        ..fontName = _latin
        ..fontSize = 9
        ..hAlign = HAlignType.left
        ..vAlign = VAlignType.center
        ..indent = 1;
      _thin(c);
    });
    ws.getRangeByIndex(totalRow, 1).setText('Amount in Total');
    final total = ws.getRangeByIndex(totalRow, 16);
    total.setFormula('=ROUND(SUM(H$firstRow:H$lastRow)+SUM(P$firstRow:P$lastRow),2)');
    total.setFormulaNumberValue(_round2(doc.total));
    total.numberFormat = '#,##0.00';
    total.cellStyle
      ..fontName = _latin
      ..fontSize = 10
      ..bold = true
      ..hAlign = HAlignType.right
      ..vAlign = VAlignType.center;
    _thin(total);

    // Signatures.
    final sigRow = totalRow + 3;
    for (final (from, to, text) in [(2, 5, "Customer's Signature"), (12, 15, 'Authorized Signature')]) {
      final r = ws.getRangeByIndex(sigRow, from, sigRow, to);
      r.merge();
      _eachCell(r, (c) {
        c.cellStyle
          ..fontName = _latin
          ..fontSize = 8
          ..hAlign = HAlignType.center
          ..borders.top.lineStyle = LineStyle.thin;
      });
      ws.getRangeByIndex(sigRow, from).setText(text);
    }

    // Print setup: one Letter page, centred.
    final ps = ws.pageSetup;
    ps.paperSize = ExcelPaperSize.paperLetter;
    ps.orientation = ExcelPageOrientation.portrait;
    ps.fitToPagesWide = 1;
    ps.fitToPagesTall = 1;
    ps.isCenterHorizontally = true;
    ps.topMargin = 0.3;
    ps.bottomMargin = 0.3;
    ps.leftMargin = 0.3;
    ps.rightMargin = 0.3;
    ps.printArea = 'A1:P$sigRow';

    // The library's own calc engine is not used: it mis-evaluated the total
    // and stored string results. Excel and Numbers recalculate on open, and
    // the cached numbers above are exact meanwhile.
    final bytes = wb.saveAsStream();
    wb.dispose();
    return bytes;
  }

  void _memoRow(Worksheet ws, int row, int startCol, MemoRow? r, bool shaded) {
    for (var c = 0; c < 8; c++) {
      final cell = ws.getRangeByIndex(row, startCol + c);
      final s = cell.cellStyle;
      s.fontName = c == 3 ? _bangla : _latin;
      s.fontSize = 8;
      s.hAlign = HAlignType.center;
      s.vAlign = VAlignType.center;
      if (shaded) s.backColor = _grey;
      _thin(cell);
      if (r == null) continue;
      switch (c) {
        case 0:
          cell.setText(toBengaliDigits(r.sl.toString()));
          s.fontName = _bangla;
        case 1:
          cell.setText(r.code);
        case 2:
          cell.setText(r.nameEn);
          s.wrapText = true;
        case 3:
          cell.setText(r.nameBn);
        case 4:
          cell.setText(r.size);
        case 5:
          if (r.quantity != null) cell.setNumber(r.quantity!);
          cell.numberFormat = '0.##';
        case 6:
          if (r.price != null) cell.setNumber(r.price!);
          cell.numberFormat = '#,##0.00';
        case 7:
          // Ordered rows get a live formula with the exact 2-decimal result
          // cached (so viewers show 2,558.40, never 2558.3999999999996).
          // Other rows hold a plain 0.00: a formula pointing at an empty
          // quantity cell would draw a warning triangle in Excel and Numbers.
          cell.numberFormat = '#,##0.00';
          if (r.quantity != null && r.price != null) {
            final q = _col(startCol + 5);
            final p = _col(startCol + 6);
            cell.setFormula('=ROUND($q$row*$p$row,2)');
            cell.setFormulaNumberValue(_round2(r.amount ?? r.quantity! * r.price!));
          } else {
            cell.setNumber(_round2(r.amount ?? 0));
          }
      }
    }
  }

  void _label(Range r, String text, {double size = 9}) {
    r.merge();
    _eachCell(r, (c) {
      c.cellStyle
        ..backColor = _black
        ..fontColor = _white
        ..bold = true
        ..fontName = _latin
        ..fontSize = size
        ..hAlign = HAlignType.center
        ..vAlign = VAlignType.center;
      _thin(c);
    });
    r.worksheet.getRangeByIndex(r.row, r.column).setText(text);
  }

  void _value(Range r, String text, {double size = 10}) {
    r.merge();
    _eachCell(r, (c) {
      c.cellStyle
        ..bold = true
        ..fontName = _latin
        ..fontSize = size
        ..hAlign = HAlignType.left
        ..vAlign = VAlignType.center
        ..indent = 1;
      _thin(c);
    });
    r.worksheet.getRangeByIndex(r.row, r.column).setText(text);
  }

  void _eachCell(Range r, void Function(Range cell) f) {
    for (var row = r.row; row <= r.lastRow; row++) {
      for (var col = r.column; col <= r.lastColumn; col++) {
        f(r.worksheet.getRangeByIndex(row, col));
      }
    }
  }

  void _thin(Range r) {
    r.cellStyle.borders.all.lineStyle = LineStyle.thin;
    r.cellStyle.borders.all.color = '#000000';
  }

  void _box(Range r) {
    final b = r.cellStyle.borders;
    b.top.lineStyle = LineStyle.thin;
    b.left.lineStyle = LineStyle.thin;
    b.right.lineStyle = LineStyle.thin;
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  static String _col(int index) => String.fromCharCode('A'.codeUnitAt(0) + index - 1);

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
