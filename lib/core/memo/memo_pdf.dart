import 'dart:typed_data';

import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';

import 'bengali.dart';
import 'memo_builder.dart';

/// Renders a [MemoDocument] as a one-page Letter PDF that mirrors Daily
/// Trading's Excel memo: banner, memo/PO header block, the catalogue split
/// into two side-by-side tables, the total line and signature lines.
class MemoPdf {
  MemoPdf({required this.bannerImage});

  /// PNG/JPEG bytes of the letterhead banner.
  final Uint8List bannerImage;

  static final _money = NumberFormat('#,##0.00', 'en_US');
  static final _date = DateFormat('dd/MM/yyyy');

  // Page geometry in points (Letter: 612 x 792).
  static const double _marginX = 18;
  static const double _marginTop = 18;
  static const double _marginBottom = 14;
  static const double _contentWidth = 612 - 2 * _marginX; // Letter width 612
  static const double _bannerHeight = 62;
  static const double _infoRowHeight = 21;
  static const double _tableHeaderHeight = 17;
  static const double _totalRowHeight = 16;
  static const double _signatureBlockHeight = 46;
  static const double _maxRowHeight = 15.4;
  static const double _minRowHeight = 9;

  /// Column widths for one half of the table (sum 288).
  static const List<double> _half = [12, 50, 62, 46, 26, 21, 30, 41];

  static const _grey = PdfColor.fromInt(0xFFEDEDED);
  static const _border = pw.BorderSide(width: 0.5);

  Future<Uint8List> render(MemoDocument doc) async {
    final regular = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();
    final banner = pw.MemoryImage(bannerImage);

    final rowsPerColumn = (doc.rows.length + 1) ~/ 2;
    final available = PdfPageFormat.letter.height -
        _marginTop -
        _marginBottom -
        _bannerHeight -
        2 * _infoRowHeight -
        _tableHeaderHeight -
        _totalRowHeight -
        _signatureBlockHeight;
    final rowHeight = rowsPerColumn == 0
        ? _maxRowHeight
        : (available / rowsPerColumn).clamp(_minRowHeight, _maxRowHeight).toDouble();
    final fontSize = rowHeight >= 14 ? 6.5 : (rowHeight >= 12 ? 6.0 : 5.5);

    final pdf = pw.Document(
      title: 'Memo ${doc.memoNumber} - ${doc.outletDisplayName}',
      author: 'Daily Trading Corporation',
      creator: 'Daily Trading Bill Generator',
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.only(left: _marginX, right: _marginX, top: _marginTop, bottom: _marginBottom),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // The letterhead is centred at its own proportions and spans the
            // content width, like the Excel memo.
            pw.Container(
              height: _bannerHeight,
              width: _contentWidth,
              decoration: const pw.BoxDecoration(border: pw.Border(top: _border, left: _border, right: _border)),
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              alignment: pw.Alignment.center,
              child: pw.Image(banner, fit: pw.BoxFit.contain),
            ),
            _infoBlock(doc, regular, bold),
            _table(doc, rowsPerColumn, rowHeight, fontSize, regular, bold),
            _totalRow(doc, bold),
            pw.SizedBox(height: 28),
            _signatures(regular),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  // ---------------------------------------------------------------------------
  // Header block
  // ---------------------------------------------------------------------------

  pw.Widget _infoBlock(MemoDocument doc, pw.Font regular, pw.Font bold) {
    pw.Widget cell(String text, {bool isBold = false, double size = 8.5, pw.Alignment align = pw.Alignment.centerLeft, bool dark = false}) =>
        pw.Container(
          height: _infoRowHeight,
          alignment: align,
          color: dark ? PdfColors.black : null,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Text(
            text,
            style: pw.TextStyle(font: isBold ? bold : regular, fontSize: size, color: dark ? PdfColors.white : PdfColors.black),
            maxLines: 1,
          ),
        );

    final row1 = pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(66),
        1: pw.FixedColumnWidth(161),
        2: pw.FixedColumnWidth(180),
        3: pw.FixedColumnWidth(66),
        4: pw.FixedColumnWidth(103),
      },
      children: [
        pw.TableRow(children: [
          cell('Memo No.', isBold: true, align: pw.Alignment.center, dark: true),
          cell(doc.memoNumber.toString(), isBold: true, size: 10),
          cell(doc.poNumber, isBold: true, size: 10),
          cell('Order date:', isBold: true, size: 8, dark: true),
          cell(doc.orderDate == null ? '' : _date.format(doc.orderDate!), isBold: true, size: 9),
        ]),
      ],
    );
    final row2 = pw.Table(
      border: const pw.TableBorder(left: _border, right: _border, bottom: _border, verticalInside: _border),
      columnWidths: const {
        0: pw.FixedColumnWidth(66),
        1: pw.FixedColumnWidth(341),
        2: pw.FixedColumnWidth(66),
        3: pw.FixedColumnWidth(103),
      },
      children: [
        pw.TableRow(children: [
          cell('Name/address:', isBold: true, size: 7, align: pw.Alignment.center, dark: true),
          cell(doc.outletDisplayName, isBold: true, size: 9),
          cell('Supply Date:', isBold: true, size: 8, dark: true),
          cell(_date.format(doc.supplyDate), isBold: true, size: 10),
        ]),
      ],
    );
    return pw.Column(children: [row1, row2]);
  }

  // ---------------------------------------------------------------------------
  // Item table
  // ---------------------------------------------------------------------------

  pw.Widget _table(MemoDocument doc, int rowsPerColumn, double rowHeight, double fontSize, pw.Font regular, pw.Font bold) {
    final widths = <int, pw.TableColumnWidth>{};
    for (var i = 0; i < 16; i++) {
      widths[i] = pw.FixedColumnWidth(_half[i % 8]);
    }

    pw.Widget headerCell(String text) => pw.Container(
          height: _tableHeaderHeight,
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(horizontal: 1),
          child: pw.Text(text, style: pw.TextStyle(font: bold, fontSize: 6, color: PdfColors.white), textAlign: pw.TextAlign.center, maxLines: 2),
        );
    const headers = ['Sl.', 'Product Code', 'Product Name', 'Product Name', 'Size', 'Qty', 'Unit price', 'Amount Tk.'];

    pw.Widget dataCell(String text, {bool bangla = false, double? size}) => pw.Container(
          height: rowHeight,
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(horizontal: 1.5),
          child: pw.Text(
            text,
            style: pw.TextStyle(font: regular, fontSize: size ?? (bangla ? fontSize - 0.5 : fontSize)),
            textAlign: pw.TextAlign.center,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
          ),
        );

    List<pw.Widget> half(MemoRow? r) {
      if (r == null) return List.generate(8, (_) => dataCell(''));
      return [
        dataCell(toBengaliDigits(r.sl.toString())),
        dataCell(r.code),
        dataCell(r.nameEn, size: r.nameEn.length > 16 ? fontSize - 0.75 : null),
        dataCell(r.nameBn, bangla: true),
        dataCell(r.size),
        dataCell(r.quantity == null ? '' : _qty(r.quantity!)),
        dataCell(r.price == null ? '' : _money.format(r.price)),
        dataCell(_money.format(r.amount ?? 0)),
      ];
    }

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.black),
        children: [for (var i = 0; i < 2; i++) ...headers.map(headerCell)],
      ),
    ];
    for (var i = 0; i < rowsPerColumn; i++) {
      final left = doc.rows[i];
      final rightIndex = i + rowsPerColumn;
      final right = rightIndex < doc.rows.length ? doc.rows[rightIndex] : null;
      rows.add(pw.TableRow(
        decoration: i.isOdd ? const pw.BoxDecoration(color: _grey) : null,
        children: [...half(left), ...half(right)],
      ));
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey700),
      columnWidths: widths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  pw.Widget _totalRow(MemoDocument doc, pw.Font bold) {
    final leftWidth = _contentWidth - _half.last;
    return pw.Container(
      decoration: const pw.BoxDecoration(border: pw.Border(left: _border, right: _border, bottom: _border)),
      height: _totalRowHeight,
      child: pw.Row(children: [
        pw.Container(
          width: leftWidth,
          padding: const pw.EdgeInsets.only(left: 3),
          alignment: pw.Alignment.centerLeft,
          decoration: const pw.BoxDecoration(border: pw.Border(right: _border)),
          child: pw.Text('Amount in Total', style: const pw.TextStyle(fontSize: 8)),
        ),
        pw.Expanded(
          child: pw.Container(
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.only(right: 3),
            child: pw.Text(_money.format(doc.total), style: pw.TextStyle(font: bold, fontSize: 7.5)),
          ),
        ),
      ]),
    );
  }

  pw.Widget _signatures(pw.Font regular) {
    pw.Widget sig(String label) => pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Container(width: 95, height: 0.6, color: PdfColors.black),
          pw.SizedBox(height: 3),
          pw.Text(label, style: pw.TextStyle(font: regular, fontSize: 7.5)),
        ]);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 24),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [sig("Customer's Signature"), sig('Authorized Signature')],
      ),
    );
  }

  static String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}
