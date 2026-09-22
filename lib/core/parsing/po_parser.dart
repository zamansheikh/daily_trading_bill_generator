import 'dart:typed_data';

import '../../domain/chain.dart';
import '../../domain/models.dart';
import 'pdf_words.dart';

/// A horizontal row of words (words whose vertical centres are close).
class _Row {
  _Row(this.words);
  final List<Word> words;
  double get y => words.first.centerY;
  String get text => words.map((w) => w.text).join(' ');
  Iterable<String> get texts => words.map((w) => w.text);
}

/// Column geometry derived from a PO's table header row.
///
/// Every buyer report we have seen prints a header of
/// `Sl Code Name Unit Qnty Rate Discount Total Note [Sp]`, but the x
/// positions differ per report. The header is therefore located on the page
/// and each column's horizontal span is taken from it instead of being
/// hardcoded; a word belongs to the column whose span contains its centre.
class _Columns {
  _Columns(this.headers);

  /// Column name to the header word that names it.
  final Map<String, Word> headers;

  static const names = ['Sl', 'Code', 'Name', 'Unit', 'Qnty', 'Rate', 'Discount', 'Total', 'Note', 'Sp'];
  static const numeric = {'Qnty', 'Rate', 'Discount', 'Total', 'Sp'};

  /// Left-aligned text columns start a little before their header word.
  static const double slack = 12;

  static _Columns? fromHeader(_Row row) {
    final headers = <String, Word>{};
    for (final w in row.words) {
      final n = names.firstWhere((n) => n.toLowerCase() == w.text.toLowerCase(), orElse: () => '');
      if (n.isNotEmpty) headers.putIfAbsent(n, () => w);
    }
    const required = ['Sl', 'Code', 'Name', 'Unit', 'Qnty', 'Rate', 'Total'];
    if (required.every(headers.containsKey)) return _Columns(headers);
    return null;
  }

  static final _numberLike = RegExp(r'^-?[\d,]*\d(\.\d+)?$');

  /// Which column a word belongs to.
  ///
  /// Text columns (Sl, Code, Name, Unit, Note) are left aligned, so a word
  /// belongs to the last text column whose header starts at or before the
  /// word's left edge. Numeric columns are right aligned under their header,
  /// so a number to the right of the Unit column goes to the numeric column
  /// whose header right edge is nearest the word's right edge. This keeps a
  /// long wrapped product name out of the Unit column and a wide amount out
  /// of its neighbour.
  String columnOf(Word w) {
    final unitLeft = headers['Unit']!.left - slack;
    if (w.left >= unitLeft && _numberLike.hasMatch(w.text)) {
      String best = 'Qnty';
      double bestDist = double.infinity;
      for (final n in numeric) {
        final h = headers[n];
        if (h == null) continue;
        final d = (h.right - w.right).abs();
        if (d < bestDist) {
          bestDist = d;
          best = n;
        }
      }
      return best;
    }
    final text = headers.entries.where((e) => !numeric.contains(e.key)).toList()
      ..sort((a, b) => a.value.left.compareTo(b.value.left));
    String col = text.first.key;
    for (final e in text) {
      if (w.left >= e.value.left - slack) col = e.key;
    }
    return col;
  }
}

/// What one page contributed.
class _PageParse {
  String? poNumber;
  String date = '';
  String purchaser = '';
  String outletName = '';
  String address = '';
  String supplier = '';
  String deliverySchedule = '';
  String note = '';
  String amountInWords = '';
  double? grandTotal;
  bool hasHeader = false;
  final items = <PoItem>[];
  final warnings = <String>[];
}

/// Parses Desh Logistics style purchase orders (Daily Shopping and Best Buy)
/// into [PurchaseOrder]s.
class PoParser {
  PoParser({this.rowTolerance = 4.0});

  /// Words whose vertical centres differ by less than this are one row.
  final double rowTolerance;

  static final _money = RegExp(r'^-?[\d,]*\d\.\d{2}$');
  static final _code = RegExp(r'^\d{5,12}$');
  static final _poNumber = RegExp(r'PO-\d{2,6}-\d{2}-\d{2}-\d{4,8}');
  static final _starred = RegExp(r'^\*.*\*$');

  ParseResult parseBytes(Uint8List bytes, {required String sourceFile}) {
    final pages = extractPageWords(bytes);
    return parsePages(pages, sourceFile: sourceFile);
  }

  ParseResult parsePages(List<PageWords> pages, {required String sourceFile}) {
    final orders = <PurchaseOrder>[];
    final fileWarnings = <String>[];

    _Columns? lastColumns;
    _PageParse? current;
    var currentPages = <int>[];

    void flush() {
      if (current == null) return;
      final order = _finish(current!, currentPages, sourceFile);
      if (order != null) orders.add(order);
      current = null;
      currentPages = [];
    }

    for (final page in pages) {
      final rows = _groupRows(page.words);
      if (rows.isEmpty) continue; // blank trailing page
      final parsed = _parsePage(rows, lastColumns);
      if (parsed == null) continue;
      lastColumns = parsed.$2 ?? lastColumns;
      final pp = parsed.$1;

      final startsNewOrder = pp.poNumber != null && (current == null || current!.poNumber != pp.poNumber);
      if (startsNewOrder) flush();

      if (current == null) {
        if (pp.poNumber == null) {
          if (pp.items.isNotEmpty) {
            fileWarnings.add('Page ${page.pageNumber}: table rows found before any PO number; skipped.');
          }
          continue;
        }
        current = pp;
        currentPages = [page.pageNumber];
      } else {
        _merge(current!, pp);
        currentPages.add(page.pageNumber);
      }
    }
    flush();

    return ParseResult(sourceFile: sourceFile, orders: orders, pageCount: pages.length, warnings: fileWarnings);
  }

  // ---------------------------------------------------------------------------
  // Row grouping
  // ---------------------------------------------------------------------------

  List<_Row> _groupRows(List<Word> words) {
    final sorted = [...words]..sort((a, b) => a.centerY.compareTo(b.centerY));
    final rows = <_Row>[];
    List<Word>? bucket;
    double? bucketY;
    for (final w in sorted) {
      if (bucket == null || (w.centerY - bucketY!).abs() > rowTolerance) {
        bucket = [w];
        bucketY = w.centerY;
        rows.add(_Row(bucket));
      } else {
        bucket.add(w);
      }
    }
    for (final r in rows) {
      r.words.sort((a, b) => a.left.compareTo(b.left));
    }
    return rows;
  }

  // ---------------------------------------------------------------------------
  // Page parsing
  // ---------------------------------------------------------------------------

  (_PageParse, _Columns?)? _parsePage(List<_Row> rows, _Columns? inherited) {
    final pp = _PageParse();

    // Locate the table header, if this page has one.
    int headerIndex = -1;
    _Columns? columns;
    for (var i = 0; i < rows.length; i++) {
      final c = _Columns.fromHeader(rows[i]);
      if (c != null) {
        headerIndex = i;
        columns = c;
        pp.hasHeader = true;
        break;
      }
    }
    columns ??= inherited;

    // Metadata (only present on the first page of a PO).
    final pageText = rows.map((r) => r.text).join('\n');
    final po = _poNumber.firstMatch(pageText);
    if (po != null) pp.poNumber = po.group(0);

    final metaRows = headerIndex >= 0 ? rows.sublist(0, headerIndex) : rows;
    _readMeta(metaRows, pp);

    if (columns == null) {
      // A page without a header and without an inherited layout: nothing to
      // read as a table.
      return (pp, null);
    }

    // Table body: from the header (or page top on continuation pages) down.
    final bodyRows = headerIndex >= 0 ? rows.sublist(headerIndex + 1) : rows;
    _readBody(bodyRows, columns, pp);
    return (pp, pp.hasHeader ? columns : null);
  }

  void _readMeta(List<_Row> rows, _PageParse pp) {
    String valueAfter(_Row row, int labelWords) {
      final rest = row.words
          .skip(labelWords)
          .map((w) => w.text)
          .where((t) => t != ':' && !_starred.hasMatch(t))
          .toList();
      return rest.join(' ').replaceFirst(RegExp(r'^:\s*'), '').trim();
    }

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final t = row.texts.toList();
      if (t.isEmpty) continue;
      final first = t.first.toLowerCase();

      if (first == 'date' && pp.date.isEmpty) {
        pp.date = valueAfter(row, 1);
      } else if (first == 'purchaser') {
        pp.purchaser = valueAfter(row, 1);
      } else if (first == 'delivery' && t.length > 1 && t[1].toLowerCase().startsWith('address')) {
        pp.outletName = valueAfter(row, 2);
        // Address lines follow until the Supplier row.
        final addr = <String>[];
        for (var j = i + 1; j < rows.length; j++) {
          final nt = rows[j].texts.first.toLowerCase();
          if (nt == 'supplier' || nt == 'as') break;
          addr.add(rows[j].text);
        }
        pp.address = addr.join(', ');
      } else if (first == 'supplier') {
        final sup = <String>[valueAfter(row, 1)];
        for (var j = i + 1; j < rows.length; j++) {
          final nt = rows[j].texts.first.toLowerCase();
          if (nt == 'as' || nt == 'sl') break;
          sup.add(rows[j].text);
        }
        pp.supplier = sup.where((s) => s.isNotEmpty).join(', ');
      }
    }
  }

  void _readBody(List<_Row> rows, _Columns columns, _PageParse pp) {
    PoItem? last;
    var afterTotal = false;

    for (final row in rows) {
      final text = row.text;
      final lower = text.toLowerCase();

      if (afterTotal) {
        // Footer: delivery schedule and note.
        if (lower.startsWith('delivery schedul')) {
          pp.deliverySchedule = _afterColon(text);
        } else if (lower.startsWith('note')) {
          pp.note = _afterColon(text);
        }
        continue;
      }

      // Grand total row: "(Thirty thousand ... paisa. ) 30,433.20"
      if (lower.contains('taka') && _money.hasMatch(row.words.last.text)) {
        pp.grandTotal = _num(row.words.last.text);
        pp.amountInWords = row.words.take(row.words.length - 1).map((w) => w.text).join(' ');
        afterTotal = true;
        continue;
      }
      if (lower.startsWith('delivery schedul') || lower.startsWith('thanks') || lower.startsWith('please supply')) {
        afterTotal = true;
        if (lower.startsWith('delivery schedul')) pp.deliverySchedule = _afterColon(text);
        continue;
      }

      // Bucket words by column.
      final cols = <String, List<Word>>{};
      for (final w in row.words) {
        cols.putIfAbsent(columns.columnOf(w), () => []).add(w);
      }
      String col(String n) => (cols[n] ?? const []).map((w) => w.text).join(' ');

      final sl = col('Sl');
      final code = col('Code');
      final isItemStart = RegExp(r'^\d{1,4}$').hasMatch(sl) && _code.hasMatch(code);

      if (isItemStart) {
        final qty = _num(col('Qnty'));
        final rate = _num(col('Rate'));
        final discount = _num(col('Discount')) ?? 0;
        final total = _num(col('Total'));
        final sp = _num(col('Sp'));
        last = PoItem(
          sl: int.parse(sl),
          code: code,
          name: col('Name'),
          unit: col('Unit'),
          quantity: qty ?? 0,
          rate: rate ?? 0,
          discount: discount,
          total: total ?? 0,
          shelfPrice: sp,
        );
        pp.items.add(last);
        if (qty == null || rate == null || total == null) {
          pp.warnings.add('Line $sl ($code): numeric columns incomplete: "$text"');
        }
        continue;
      }

      // Continuation of a wrapped product name (e.g. "Jeera) 25gm").
      if (last != null && sl.isEmpty && code.isEmpty) {
        final name = col('Name');
        if (name.isNotEmpty) {
          final idx = pp.items.indexOf(last);
          pp.items[idx] = last = _withName(last, '${last.name} $name'.trim());
        }
        continue;
      }
    }
  }

  PoItem _withName(PoItem i, String name) => PoItem(
        sl: i.sl,
        code: i.code,
        name: name,
        unit: i.unit,
        quantity: i.quantity,
        rate: i.rate,
        discount: i.discount,
        total: i.total,
        shelfPrice: i.shelfPrice,
        productId: i.productId,
      );

  String _afterColon(String s) {
    final i = s.indexOf(':');
    return (i >= 0 ? s.substring(i + 1) : s.replaceFirst(RegExp(r'^\S+(\s\S+)?'), '')).trim();
  }

  double? _num(String s) {
    final t = s.replaceAll(',', '').trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  // ---------------------------------------------------------------------------
  // Assembly
  // ---------------------------------------------------------------------------

  void _merge(_PageParse into, _PageParse from) {
    into.items.addAll(from.items);
    into.warnings.addAll(from.warnings);
    into.grandTotal ??= from.grandTotal;
    if (into.amountInWords.isEmpty) into.amountInWords = from.amountInWords;
    if (into.deliverySchedule.isEmpty) into.deliverySchedule = from.deliverySchedule;
    if (into.note.isEmpty) into.note = from.note;
  }

  PurchaseOrder? _finish(_PageParse pp, List<int> pages, String sourceFile) {
    if (pp.poNumber == null) return null;
    final warnings = [...pp.warnings];

    // Arithmetic checks make the parse self-verifying.
    for (final it in pp.items) {
      final expected = it.quantity * it.rate - it.discount;
      if ((expected - it.total).abs() > 0.05) {
        warnings.add('Line ${it.sl}: ${it.quantity} x ${it.rate} = ${expected.toStringAsFixed(2)} but PO says ${it.total.toStringAsFixed(2)}');
      }
    }
    for (var i = 1; i < pp.items.length; i++) {
      if (pp.items[i].sl != pp.items[i - 1].sl + 1) {
        warnings.add('Serial jumps from ${pp.items[i - 1].sl} to ${pp.items[i].sl}; a line may be missing.');
      }
    }
    final computed = pp.items.fold(0.0, (s, i) => s + i.total);
    if (pp.grandTotal == null) {
      warnings.add('Grand total not found on the PO; parsed lines sum to ${computed.toStringAsFixed(2)}.');
    } else if ((pp.grandTotal! - computed).abs() > 0.05) {
      warnings.add('Parsed lines sum to ${computed.toStringAsFixed(2)} but PO total is ${pp.grandTotal!.toStringAsFixed(2)}.');
    }
    if (pp.items.isEmpty) warnings.add('No item lines found.');

    final chain = Chain.detect(
      outletName: pp.outletName,
      poNumber: pp.poNumber!,
      codes: pp.items.map((i) => i.code),
    );

    return PurchaseOrder(
      poNumber: pp.poNumber!,
      chain: chain,
      poDate: pp.date,
      purchaser: pp.purchaser,
      outletName: pp.outletName,
      address: pp.address,
      supplier: pp.supplier,
      items: pp.items,
      declaredTotal: pp.grandTotal,
      amountInWords: pp.amountInWords,
      deliverySchedule: pp.deliverySchedule,
      note: pp.note,
      sourceFile: sourceFile,
      pages: pages,
      warnings: warnings,
    );
  }
}
