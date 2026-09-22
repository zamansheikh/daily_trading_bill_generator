import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/catalog/catalog.dart';
import '../../core/catalog/product_matcher.dart';
import '../../core/memo/memo_builder.dart';
import '../../core/memo/memo_pdf.dart';
import '../../core/parsing/po_parser.dart';
import '../../data/app_database.dart';
import '../../domain/chain.dart';
import '../../domain/models.dart';

/// An order in the current working set: parsed, matched and editable.
class ImportedOrder {
  ImportedOrder({required this.po, required this.outletDisplayName, required this.matchKinds, this.memoNumber, this.memoPath});

  PurchaseOrder po;
  String outletDisplayName;

  /// Per item (by index) how it was matched.
  List<MatchKind> matchKinds;
  int? memoNumber;
  String? memoPath;
  bool selected = true;

  bool get hasUnmatched => matchKinds.contains(MatchKind.none);
  bool get hasWarnings => po.warnings.isNotEmpty;
  bool get isClean => !hasUnmatched && !hasWarnings && po.totalsMatch;
  int get unmatchedCount => matchKinds.where((k) => k == MatchKind.none).length;
}

class ImportSummary {
  ImportSummary({required this.files, required this.orders, required this.errors});
  final int files;
  final int orders;
  final List<String> errors;
}

class GenerateResult {
  GenerateResult({required this.generated, required this.errors, required this.outputDir});
  final List<ImportedOrder> generated;
  final List<String> errors;
  final String outputDir;
}

/// Application state: catalogue, working set of imported orders, settings.
class AppState extends ChangeNotifier {
  AppState({required this.db, required this.bannerBytes});

  final AppDatabase db;
  final Uint8List bannerBytes;

  late Catalog catalog;
  late ProductMatcher matcher;
  final parser = PoParser();

  final List<ImportedOrder> orders = [];
  List<StoredOrder> history = [];

  int nextMemoNumber = 1;
  String outputDir = '';
  bool learnPrices = true;
  DateTime supplyDate = DateTime.now();
  bool busy = false;
  String busyMessage = '';

  Future<void> init() async {
    await _reloadCatalog();
    nextMemoNumber = int.tryParse(await db.getSetting('next_memo_number') ?? '1') ?? 1;
    learnPrices = (await db.getSetting('learn_prices') ?? '1') == '1';
    outputDir = await db.getSetting('output_dir') ?? await _defaultOutputDir();
    await refreshHistory();
    notifyListeners();
  }

  Future<String> _defaultOutputDir() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      return p.join(docs.path, 'Daily Trading Memos');
    } catch (_) {
      // No platform plugin (tests, headless runs): fall back to a local folder.
      return p.join(Directory.current.path, 'Daily Trading Memos');
    }
  }

  Future<void> _reloadCatalog() async {
    catalog = await db.loadCatalog();
    matcher = ProductMatcher(catalog);
  }

  Future<void> refreshHistory() async {
    history = await db.listMemos();
    notifyListeners();
  }

  void _setBusy(bool value, [String message = '']) {
    busy = value;
    busyMessage = message;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  Future<ImportSummary> importFiles(List<String> paths) async {
    final errors = <String>[];
    var count = 0;
    _setBusy(true, 'Reading purchase orders...');
    try {
      for (final path in paths) {
        try {
          final bytes = await File(path).readAsBytes();
          final result = await compute(_parseInIsolate, (bytes, p.basename(path)));
          errors.addAll(result.warnings.map((w) => '${p.basename(path)}: $w'));
          if (result.orders.isEmpty) errors.add('${p.basename(path)}: no purchase orders found.');
          for (final po in result.orders) {
            await _addOrder(po);
            count++;
          }
        } catch (e) {
          errors.add('${p.basename(path)}: $e');
        }
      }
    } finally {
      _setBusy(false);
    }
    return ImportSummary(files: paths.length, orders: count, errors: errors);
  }

  static ParseResult _parseInIsolate((Uint8List, String) args) =>
      PoParser().parseBytes(args.$1, sourceFile: args.$2);

  Future<void> _addOrder(PurchaseOrder po) async {
    final kinds = <MatchKind>[];
    for (final it in po.items) {
      final m = matcher.match(po.chain, it);
      it.productId = m.product?.id;
      kinds.add(m.kind);
      if (m.kind == MatchKind.name && m.product != null) {
        // Remember the buyer's code so the next PO matches by code.
        await db.saveAlias(po.chain, it.code, m.product!.id);
      }
    }
    final display = await db.outletDisplayName(po.outletName) ?? defaultOutletDisplayName(po.outletName);
    final existing = await db.getOrder(po.poNumber);
    await db.saveOrder(po, outletDisplayName: display);

    final imported = ImportedOrder(
      po: po,
      outletDisplayName: display,
      matchKinds: kinds,
      memoNumber: existing?.memoNumber,
      memoPath: existing?.memoPath,
    );
    orders.removeWhere((o) => o.po.poNumber == po.poNumber);
    orders.add(imported);
    if (kinds.contains(MatchKind.name)) await _reloadCatalog();
    notifyListeners();
  }

  /// Puts a previously stored order back into the working list, keeping its
  /// memo number so regenerating overwrites the same memo.
  void loadStoredOrder(StoredOrder stored) {
    final kinds = stored.po.items.map((it) => it.productId == null ? MatchKind.none : MatchKind.code).toList();
    orders.removeWhere((o) => o.po.poNumber == stored.po.poNumber);
    orders.add(ImportedOrder(
      po: stored.po,
      outletDisplayName: stored.outletDisplayName,
      matchKinds: kinds,
      memoNumber: stored.memoNumber,
      memoPath: stored.memoPath,
    ));
    notifyListeners();
  }

  void removeOrder(ImportedOrder o) {
    orders.remove(o);
    notifyListeners();
  }

  void clearOrders() {
    orders.clear();
    notifyListeners();
  }

  void toggleSelected(ImportedOrder o, bool value) {
    o.selected = value;
    notifyListeners();
  }

  void selectAll(bool value) {
    for (final o in orders) {
      o.selected = value;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Editing
  // ---------------------------------------------------------------------------

  Future<void> setOutletDisplayName(ImportedOrder o, String name) async {
    o.outletDisplayName = name.trim();
    await db.saveOutletDisplayName(o.po.outletName, o.outletDisplayName);
    await db.saveOrder(o.po, outletDisplayName: o.outletDisplayName);
    notifyListeners();
  }

  Future<void> setItemProduct(ImportedOrder o, int index, Product? product) async {
    final it = o.po.items[index];
    it.productId = product?.id;
    o.matchKinds[index] = product == null ? MatchKind.none : MatchKind.name;
    if (product != null) await db.saveAlias(o.po.chain, it.code, product.id);
    await db.saveOrder(o.po, outletDisplayName: o.outletDisplayName);
    await _reloadCatalog();
    notifyListeners();
  }

  Future<void> setItemQuantity(ImportedOrder o, int index, double qty) async {
    final it = o.po.items[index];
    final updated = it.copyWith(quantity: qty, total: double.parse((qty * it.rate - it.discount).toStringAsFixed(2)));
    o.po.items[index] = updated;
    await db.saveOrder(o.po, outletDisplayName: o.outletDisplayName);
    notifyListeners();
  }

  Future<void> setItemRate(ImportedOrder o, int index, double rate) async {
    final it = o.po.items[index];
    final updated = it.copyWith(rate: rate, total: double.parse((it.quantity * rate - it.discount).toStringAsFixed(2)));
    o.po.items[index] = updated;
    await db.saveOrder(o.po, outletDisplayName: o.outletDisplayName);
    notifyListeners();
  }

  void setSupplyDate(DateTime d) {
    supplyDate = d;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Memo generation
  // ---------------------------------------------------------------------------

  MemoDocument buildMemo(ImportedOrder o, {int? memoNumber}) => MemoBuilder(catalog).build(
        o.po,
        memoNumber: memoNumber ?? o.memoNumber ?? nextMemoNumber,
        supplyDate: supplyDate,
        outletDisplayName: o.outletDisplayName,
      );

  Future<Uint8List> renderMemo(MemoDocument doc) => MemoPdf(bannerImage: bannerBytes).render(doc);

  /// File name in the style of the reference memos: "9808(BBUY Grocery Mogbazar).pdf".
  static String memoFileName(int memoNumber, String outlet) {
    final safe = outlet.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return '$memoNumber($safe).pdf';
  }

  Future<GenerateResult> generateMemos(List<ImportedOrder> targets, {String? directory}) async {
    final dir = directory ?? p.join(outputDir, DateFormat('yyyy-MM-dd').format(supplyDate));
    await Directory(dir).create(recursive: true);
    final generated = <ImportedOrder>[];
    final errors = <String>[];
    _setBusy(true, 'Generating memos...');
    try {
      for (final o in targets) {
        try {
          final memoNumber = o.memoNumber ?? await db.takeMemoNumber();
          final doc = buildMemo(o, memoNumber: memoNumber);
          final bytes = await renderMemo(doc);
          final path = p.join(dir, memoFileName(memoNumber, o.outletDisplayName));
          await File(path).writeAsBytes(bytes, flush: true);
          o.memoNumber = memoNumber;
          o.memoPath = path;
          await db.saveMemoResult(
            poNumber: o.po.poNumber,
            memoNumber: memoNumber,
            supplyDate: supplyDate,
            memoPath: path,
            outletDisplayName: o.outletDisplayName,
          );
          if (learnPrices) await _learnPrices(o);
          generated.add(o);
        } catch (e) {
          errors.add('${o.po.poNumber}: $e');
        }
      }
      nextMemoNumber = int.tryParse(await db.getSetting('next_memo_number') ?? '1') ?? 1;
      if (learnPrices) await _reloadCatalog();
      await refreshHistory();
    } finally {
      _setBusy(false);
    }
    return GenerateResult(generated: generated, errors: errors, outputDir: dir);
  }

  /// The rate on the newest PO becomes the chain's list price for that
  /// product, so memos for other outlets show current prices.
  Future<void> _learnPrices(ImportedOrder o) async {
    final chain = o.po.chain == Chain.unknown ? Chain.dailyShopping : o.po.chain;
    for (final it in o.po.items) {
      if (it.productId == null || it.rate <= 0) continue;
      if (catalog.price(chain, it.productId!) != it.rate) {
        await db.savePrice(chain, it.productId!, it.rate);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Settings and catalogue maintenance
  // ---------------------------------------------------------------------------

  Future<void> setNextMemoNumber(int n) async {
    nextMemoNumber = n;
    await db.setSetting('next_memo_number', '$n');
    notifyListeners();
  }

  Future<void> setOutputDir(String dir) async {
    outputDir = dir;
    await db.setSetting('output_dir', dir);
    notifyListeners();
  }

  Future<void> setLearnPrices(bool v) async {
    learnPrices = v;
    await db.setSetting('learn_prices', v ? '1' : '0');
    notifyListeners();
  }

  Future<void> saveProduct(Product pr, {required Map<Chain, ChainProduct> chains}) async {
    final id = await db.saveProduct(pr);
    for (final cp in chains.values) {
      await db.saveChainProduct(ChainProduct(chain: cp.chain, productId: id, included: cp.included, price: cp.price));
    }
    await _reloadCatalog();
    notifyListeners();
  }

  Future<void> deleteProduct(int id) async {
    await db.deleteProduct(id);
    await _reloadCatalog();
    notifyListeners();
  }

  Future<void> saveAlias(Chain chain, String code, int productId) async {
    await db.saveAlias(chain, code, productId);
    await _reloadCatalog();
    notifyListeners();
  }

  Future<void> deleteStoredOrder(String poNumber) async {
    await db.deleteOrder(poNumber);
    orders.removeWhere((o) => o.po.poNumber == poNumber);
    await refreshHistory();
  }
}
