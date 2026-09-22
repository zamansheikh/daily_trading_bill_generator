import 'chain.dart';

/// One line of a purchase order exactly as printed by the buyer.
class PoItem {
  PoItem({
    required this.sl,
    required this.code,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.rate,
    required this.discount,
    required this.total,
    this.shelfPrice,
    this.productId,
  });

  final int sl;

  /// The buyer's product code (6 digits for Best Buy, 10 for Daily Shopping).
  final String code;

  /// Raw name from the PO, e.g. "Daily Shopping Almond 100gm".
  final String name;
  final String unit;
  final double quantity;
  final double rate;
  final double discount;
  final double total;

  /// Shelf price ("Sp" column) when the PO carries one.
  final double? shelfPrice;

  /// Catalogue product this line was matched to, if any.
  int? productId;

  /// Name without the "Daily Shopping" prefix, for display.
  String get cleanName => name
      .replaceFirst(RegExp(r'^\s*Daily\s+Shopping\s*[-:]?\s*', caseSensitive: false), '')
      .trim();

  PoItem copyWith({
    double? quantity,
    double? rate,
    double? total,
    int? productId,
    bool clearProduct = false,
  }) =>
      PoItem(
        sl: sl,
        code: code,
        name: name,
        unit: unit,
        quantity: quantity ?? this.quantity,
        rate: rate ?? this.rate,
        discount: discount,
        total: total ?? this.total,
        shelfPrice: shelfPrice,
        productId: clearProduct ? null : (productId ?? this.productId),
      );

  Map<String, dynamic> toJson() => {
        'sl': sl,
        'code': code,
        'name': name,
        'unit': unit,
        'quantity': quantity,
        'rate': rate,
        'discount': discount,
        'total': total,
        'shelfPrice': shelfPrice,
        'productId': productId,
      };

  factory PoItem.fromJson(Map<String, dynamic> j) => PoItem(
        sl: (j['sl'] as num).toInt(),
        code: j['code'] as String,
        name: j['name'] as String,
        unit: j['unit'] as String? ?? '',
        quantity: (j['quantity'] as num).toDouble(),
        rate: (j['rate'] as num).toDouble(),
        discount: (j['discount'] as num?)?.toDouble() ?? 0,
        total: (j['total'] as num).toDouble(),
        shelfPrice: (j['shelfPrice'] as num?)?.toDouble(),
        productId: (j['productId'] as num?)?.toInt(),
      );
}

/// A purchase order parsed from a buyer's PDF.
class PurchaseOrder {
  PurchaseOrder({
    required this.poNumber,
    required this.chain,
    required this.poDate,
    required this.purchaser,
    required this.outletName,
    required this.address,
    required this.supplier,
    required this.items,
    required this.declaredTotal,
    required this.amountInWords,
    required this.deliverySchedule,
    required this.note,
    required this.sourceFile,
    required this.pages,
    List<String>? warnings,
    List<PoItem>? removedItems,
  })  : warnings = warnings ?? [],
        removedItems = removedItems ?? [];

  final String poNumber;
  final Chain chain;

  /// Date as printed, e.g. "16-Sep-2026".
  final String poDate;
  final String purchaser;

  /// Outlet name as printed on the PO, e.g. "BBUY-Mogbazar-Wireless Gate".
  final String outletName;
  final String address;
  final String supplier;
  final List<PoItem> items;

  /// Grand total printed on the PO (used to verify the parse).
  final double? declaredTotal;
  final String amountInWords;
  final String deliverySchedule;
  final String note;
  final String sourceFile;

  /// 1-based page numbers of the source file this PO occupies.
  final List<int> pages;
  final List<String> warnings;

  /// Lines the user removed from the memo (e.g. out of stock). They are kept
  /// so the parse can still be reconciled against the PO's printed total and
  /// so a removal can be undone.
  final List<PoItem> removedItems;

  double get computedTotal => items.fold(0.0, (s, i) => s + i.total);

  double get removedTotal => removedItems.fold(0.0, (s, i) => s + i.total);

  /// True when the lines (including any the user removed) add up to the
  /// total printed on the PO.
  bool get totalsMatch =>
      declaredTotal != null && (declaredTotal! - computedTotal - removedTotal).abs() < 0.05;

  /// Moves the line at [index] to [removedItems].
  PoItem removeItemAt(int index) {
    final it = items.removeAt(index);
    removedItems.add(it);
    return it;
  }

  /// Puts a removed line back, in serial order.
  void restoreItem(PoItem it) {
    removedItems.remove(it);
    items.add(it);
    items.sort((a, b) => a.sl.compareTo(b.sl));
  }

  DateTime? get poDateTime => parsePoDate(poDate);

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  Map<String, dynamic> toJson() => {
        'poNumber': poNumber,
        'chain': chain.id,
        'poDate': poDate,
        'purchaser': purchaser,
        'outletName': outletName,
        'address': address,
        'supplier': supplier,
        'items': items.map((i) => i.toJson()).toList(),
        'declaredTotal': declaredTotal,
        'amountInWords': amountInWords,
        'deliverySchedule': deliverySchedule,
        'note': note,
        'sourceFile': sourceFile,
        'pages': pages,
        'warnings': warnings,
        'removedItems': removedItems.map((i) => i.toJson()).toList(),
      };

  factory PurchaseOrder.fromJson(Map<String, dynamic> j) => PurchaseOrder(
        poNumber: j['poNumber'] as String,
        chain: Chain.fromId(j['chain'] as String?),
        poDate: j['poDate'] as String? ?? '',
        purchaser: j['purchaser'] as String? ?? '',
        outletName: j['outletName'] as String? ?? '',
        address: j['address'] as String? ?? '',
        supplier: j['supplier'] as String? ?? '',
        items: (j['items'] as List).map((e) => PoItem.fromJson(e as Map<String, dynamic>)).toList(),
        declaredTotal: (j['declaredTotal'] as num?)?.toDouble(),
        amountInWords: j['amountInWords'] as String? ?? '',
        deliverySchedule: j['deliverySchedule'] as String? ?? '',
        note: j['note'] as String? ?? '',
        sourceFile: j['sourceFile'] as String? ?? '',
        pages: (j['pages'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
        warnings: (j['warnings'] as List? ?? const []).cast<String>(),
        removedItems: (j['removedItems'] as List? ?? const []).map((e) => PoItem.fromJson(e as Map<String, dynamic>)).toList(),
      );

  /// Parses "16-Sep-2026" style dates.
  static DateTime? parsePoDate(String s) {
    final m = RegExp(r'(\d{1,2})-([A-Za-z]{3})[a-z]*-(\d{4})').firstMatch(s);
    if (m == null) return null;
    final month = _months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime(int.parse(m.group(3)!), month, int.parse(m.group(1)!));
  }
}

/// Result of parsing one PDF file.
class ParseResult {
  ParseResult({required this.sourceFile, required this.orders, required this.pageCount, List<String>? warnings})
      : warnings = warnings ?? [];
  final String sourceFile;
  final List<PurchaseOrder> orders;
  final int pageCount;
  final List<String> warnings;
}

/// A product in Daily Trading's own catalogue.
class Product {
  Product({
    required this.id,
    required this.dtCode,
    required this.nameEn,
    required this.nameBn,
    required this.size,
    required this.sortOrder,
    this.active = true,
  });

  final int id;
  final String dtCode;
  final String nameEn;
  final String nameBn;
  final String size;
  final int sortOrder;
  final bool active;

  Product copyWith({String? dtCode, String? nameEn, String? nameBn, String? size, int? sortOrder, bool? active}) =>
      Product(
        id: id,
        dtCode: dtCode ?? this.dtCode,
        nameEn: nameEn ?? this.nameEn,
        nameBn: nameBn ?? this.nameBn,
        size: size ?? this.size,
        sortOrder: sortOrder ?? this.sortOrder,
        active: active ?? this.active,
      );
}

/// Chain specific settings for a product: whether it is printed on that
/// chain's memo and the unit price shown for it.
class ChainProduct {
  ChainProduct({required this.chain, required this.productId, required this.included, this.price});
  final Chain chain;
  final int productId;
  final bool included;
  final double? price;
}

/// A memo that was generated for a purchase order.
class MemoRecord {
  MemoRecord({
    required this.poNumber,
    required this.memoNumber,
    required this.chain,
    required this.outletDisplayName,
    required this.supplyDate,
    required this.total,
    required this.filePath,
    required this.generatedAt,
  });
  final String poNumber;
  final int memoNumber;
  final Chain chain;
  final String outletDisplayName;
  final DateTime supplyDate;
  final double total;
  final String filePath;
  final DateTime generatedAt;
}
