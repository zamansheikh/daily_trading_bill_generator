import '../../domain/chain.dart';
import '../../domain/models.dart';
import '../catalog/catalog.dart';

/// One printed line of the memo table.
class MemoRow {
  MemoRow({
    required this.sl,
    required this.code,
    required this.nameEn,
    required this.nameBn,
    required this.size,
    this.quantity,
    this.price,
    this.amount,
    this.isExtra = false,
  });

  final int sl;
  final String code;
  final String nameEn;
  final String nameBn;
  final String size;

  /// Ordered quantity; null when this product was not on the PO.
  final double? quantity;

  /// Unit price shown; null prints as blank.
  final double? price;

  /// Line amount; null prints as 0.00.
  final double? amount;

  /// True for a PO line that is not in the catalogue and was appended.
  final bool isExtra;
}

/// Everything the memo page needs.
class MemoDocument {
  MemoDocument({
    required this.memoNumber,
    required this.poNumber,
    required this.orderDate,
    required this.outletDisplayName,
    required this.supplyDate,
    required this.rows,
    required this.total,
    required this.chain,
  });

  final int memoNumber;
  final String poNumber;
  final DateTime? orderDate;
  final String outletDisplayName;
  final DateTime supplyDate;
  final List<MemoRow> rows;
  final double total;
  final Chain chain;
}

/// Builds the memo rows for a purchase order: the chain's full catalogue in
/// print order, with quantity, unit price and amount filled in from the PO
/// for the products that were ordered and the chain's list price for the
/// rest. PO lines that match no catalogue product are appended at the end so
/// nothing ordered is ever silently dropped.
class MemoBuilder {
  MemoBuilder(this.catalog);
  final Catalog catalog;

  MemoDocument build(
    PurchaseOrder po, {
    required int memoNumber,
    required DateTime supplyDate,
    required String outletDisplayName,
  }) {
    final chain = po.chain == Chain.unknown ? Chain.dailyShopping : po.chain;
    final ordered = <int, PoItem>{};
    final extras = <PoItem>[];
    for (final it in po.items) {
      final pid = it.productId;
      if (pid == null || catalog.byId(pid) == null) {
        extras.add(it);
      } else if (ordered.containsKey(pid)) {
        // Same product twice on one PO: merge the quantities.
        final prev = ordered[pid]!;
        ordered[pid] = prev.copyWith(quantity: prev.quantity + it.quantity, total: prev.total + it.total);
      } else {
        ordered[pid] = it;
      }
    }

    final rows = <MemoRow>[];
    var sl = 0;
    for (final p in catalog.productsFor(chain)) {
      sl++;
      final it = ordered.remove(p.id);
      rows.add(MemoRow(
        sl: sl,
        code: p.dtCode,
        nameEn: p.nameEn,
        nameBn: p.nameBn,
        size: p.size,
        quantity: it?.quantity,
        price: it?.rate ?? catalog.price(chain, p.id),
        amount: it?.total,
      ));
    }
    // Ordered products that exist in the catalogue but are switched off for
    // this chain still have to be billed.
    for (final it in ordered.values) {
      final p = catalog.byId(it.productId)!;
      sl++;
      rows.add(MemoRow(sl: sl, code: p.dtCode, nameEn: p.nameEn, nameBn: p.nameBn, size: p.size, quantity: it.quantity, price: it.rate, amount: it.total, isExtra: true));
    }
    for (final it in extras) {
      sl++;
      final size = it.name.contains(RegExp(r'\d')) ? _sizeOf(it.name) : '';
      rows.add(MemoRow(
        sl: sl,
        code: it.code,
        nameEn: it.cleanName.replaceAll(size, '').trim(),
        nameBn: '',
        size: size,
        quantity: it.quantity,
        price: it.rate,
        amount: it.total,
        isExtra: true,
      ));
    }

    return MemoDocument(
      memoNumber: memoNumber,
      poNumber: po.poNumber,
      orderDate: po.poDateTime,
      outletDisplayName: outletDisplayName,
      supplyDate: supplyDate,
      rows: rows,
      total: po.computedTotal,
      chain: chain,
    );
  }

  static String _sizeOf(String name) =>
      RegExp(r'\d+(?:\.\d+)?\s*(?:kg|gm|g|ml|l)\b', caseSensitive: false).firstMatch(name)?.group(0) ?? '';
}

/// Notes that are just a delivery mode, not a destination.
const _genericNotes = {'', 'po', 'dsd', 'dd', 'direct'};

/// True when the PO's Note names the real destination: the delivery address
/// is a central warehouse and the note says which outlet the goods are for
/// ("Daily Shopping - DLCL-WARE HOUSE-PATIRA" + note "BARISHAL-2").
bool noteIsDestination(String outletName, String note) {
  final n = note.trim().toLowerCase();
  if (_genericNotes.contains(n)) return false;
  final o = outletName.toLowerCase();
  return o.contains('ware house') || o.contains('warehouse') || o.contains('dlcl');
}

/// Key under which a display name is remembered for an outlet. Warehouse POs
/// are keyed by destination so each outlet keeps its own name.
String outletKey(String outletName, String note) =>
    noteIsDestination(outletName, note) ? '$outletName | ${note.trim()}' : outletName;

/// Default display name for an outlet: the PO's outlet name with the hyphens
/// the buyer's system inserts turned back into spaces.
/// "BBUY-Mogbazar-Wireless Gate" -> "BBUY Mogbazar Wireless Gate".
/// When the note names the destination (warehouse delivery), the address is
/// kept as printed and the note is appended in brackets:
/// "Daily Shopping - DLCL-WARE HOUSE-PATIRA" + "BARISHAL-2"
///   -> "Daily Shopping - DLCL-WARE HOUSE-PATIRA (BARISHAL-2)".
String defaultOutletDisplayName(String poOutletName, {String note = ''}) {
  var s = poOutletName.trim();
  if (noteIsDestination(s, note)) return '$s (${note.trim()})';
  s = s.replaceAll(RegExp(r'\s*-\s*'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s.trim();
}
