import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/catalog/catalog.dart';
import '../core/catalog/seed_catalog.dart';
import '../domain/chain.dart';
import '../domain/models.dart';

/// A purchase order as stored, with the memo bookkeeping that belongs to it.
class StoredOrder {
  StoredOrder({
    required this.po,
    required this.outletDisplayName,
    required this.importedAt,
    this.memoNumber,
    this.supplyDate,
    this.memoPath,
    this.generatedAt,
  });

  final PurchaseOrder po;
  final String outletDisplayName;
  final DateTime importedAt;
  final int? memoNumber;
  final DateTime? supplyDate;
  final String? memoPath;
  final DateTime? generatedAt;

  bool get hasMemo => memoNumber != null;
}

/// SQLite persistence. Works on Windows, macOS and Linux through
/// sqflite_common_ffi and on Android/iOS through sqflite.
class AppDatabase {
  AppDatabase._(this._db);
  final Database _db;

  static const _version = 1;

  static Future<AppDatabase> open({String? path}) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dbPath = path ?? p.join((await getApplicationSupportDirectory()).path, 'daily_trading_bills.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: _version, onCreate: _create),
    );
    final app = AppDatabase._(db);
    await app._seedIfEmpty();
    return app;
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dt_code TEXT NOT NULL,
        name_en TEXT NOT NULL,
        name_bn TEXT NOT NULL DEFAULT '',
        size TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('''
      CREATE TABLE chain_products (
        chain TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        included INTEGER NOT NULL DEFAULT 1,
        price REAL,
        PRIMARY KEY (chain, product_id)
      )''');
    await db.execute('''
      CREATE TABLE code_aliases (
        chain TEXT NOT NULL,
        code TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        PRIMARY KEY (chain, code)
      )''');
    await db.execute('''
      CREATE TABLE outlets (
        po_name TEXT PRIMARY KEY,
        display_name TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE purchase_orders (
        po_number TEXT PRIMARY KEY,
        chain TEXT NOT NULL,
        po_date TEXT,
        outlet_po_name TEXT,
        outlet_display TEXT,
        total REAL,
        json TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        memo_number INTEGER,
        supply_date TEXT,
        memo_path TEXT,
        generated_at TEXT
      )''');
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
  }

  Future<void> _seedIfEmpty() async {
    final n = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM products')) ?? 0;
    if (n > 0) return;
    await _seed();
  }

  /// Throws away every product, price and code alias and reloads the
  /// catalogue that ships with the app. Orders, memos and settings are kept.
  Future<void> resetCatalogToDefaults() async {
    await _db.delete('products');
    await _db.delete('chain_products');
    await _db.delete('code_aliases');
    await _seed();
  }

  Future<void> _seed() async {
    final seed = SeedCatalog.build();
    await _db.transaction((txn) async {
      final idMap = <int, int>{};
      for (final pr in seed.products) {
        idMap[pr.id] = await txn.insert('products', {
          'dt_code': pr.dtCode,
          'name_en': pr.nameEn,
          'name_bn': pr.nameBn,
          'size': pr.size,
          'sort_order': pr.sortOrder,
          'active': 1,
        });
      }
      for (final pr in seed.products) {
        for (final chain in [Chain.dailyShopping, Chain.bestBuy]) {
          final cp = seed.chainProduct(chain, pr.id)!;
          await txn.insert('chain_products', {
            'chain': chain.id,
            'product_id': idMap[pr.id],
            'included': cp.included ? 1 : 0,
            'price': cp.price,
          });
        }
      }
      for (final e in SeedCatalog.bestBuyAliases.entries) {
        final pid = seed.byDtCode(e.value)!.id;
        await txn.insert('code_aliases', {'chain': Chain.bestBuy.id, 'code': e.key, 'product_id': idMap[pid]});
      }
      await txn.insert('settings', {'key': 'next_memo_number', 'value': '1'}, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  // ---------------------------------------------------------------------------
  // Catalogue
  // ---------------------------------------------------------------------------

  Future<Catalog> loadCatalog() async {
    final products = (await _db.query('products', orderBy: 'sort_order, id'))
        .map((r) => Product(
              id: r['id'] as int,
              dtCode: r['dt_code'] as String,
              nameEn: r['name_en'] as String,
              nameBn: r['name_bn'] as String? ?? '',
              size: r['size'] as String? ?? '',
              sortOrder: r['sort_order'] as int? ?? 0,
              active: (r['active'] as int? ?? 1) == 1,
            ))
        .toList();
    final cps = (await _db.query('chain_products'))
        .map((r) => ChainProduct(
              chain: Chain.fromId(r['chain'] as String),
              productId: r['product_id'] as int,
              included: (r['included'] as int) == 1,
              price: (r['price'] as num?)?.toDouble(),
            ))
        .toList();
    final aliases = (await _db.query('code_aliases'))
        .map((r) => (Chain.fromId(r['chain'] as String), r['code'] as String, r['product_id'] as int))
        .toList();
    return Catalog(products: products, chainProducts: cps, aliases: aliases);
  }

  /// Inserts (id == 0) or updates a product. Returns its id.
  Future<int> saveProduct(Product pr) async {
    final row = {
      'dt_code': pr.dtCode.trim(),
      'name_en': pr.nameEn.trim(),
      'name_bn': pr.nameBn.trim(),
      'size': pr.size.trim(),
      'sort_order': pr.sortOrder,
      'active': pr.active ? 1 : 0,
    };
    if (pr.id == 0) return _db.insert('products', row);
    await _db.update('products', row, where: 'id = ?', whereArgs: [pr.id]);
    return pr.id;
  }

  Future<void> deleteProduct(int id) async {
    await _db.delete('products', where: 'id = ?', whereArgs: [id]);
    await _db.delete('chain_products', where: 'product_id = ?', whereArgs: [id]);
    await _db.delete('code_aliases', where: 'product_id = ?', whereArgs: [id]);
  }

  Future<void> saveChainProduct(ChainProduct cp) => _db.insert(
        'chain_products',
        {'chain': cp.chain.id, 'product_id': cp.productId, 'included': cp.included ? 1 : 0, 'price': cp.price},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> savePrice(Chain chain, int productId, double? price) async {
    final n = await _db.update('chain_products', {'price': price}, where: 'chain = ? AND product_id = ?', whereArgs: [chain.id, productId]);
    if (n == 0) await saveChainProduct(ChainProduct(chain: chain, productId: productId, included: true, price: price));
  }

  Future<void> saveAlias(Chain chain, String code, int productId) => _db.insert(
        'code_aliases',
        {'chain': chain.id, 'code': code, 'product_id': productId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteAlias(Chain chain, String code) =>
      _db.delete('code_aliases', where: 'chain = ? AND code = ?', whereArgs: [chain.id, code]);

  // ---------------------------------------------------------------------------
  // Outlets
  // ---------------------------------------------------------------------------

  Future<String?> outletDisplayName(String poName) async {
    final r = await _db.query('outlets', where: 'po_name = ?', whereArgs: [poName]);
    return r.isEmpty ? null : r.first['display_name'] as String;
  }

  Future<void> saveOutletDisplayName(String poName, String display) => _db.insert(
        'outlets',
        {'po_name': poName, 'display_name': display},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  // ---------------------------------------------------------------------------
  // Orders and memos
  // ---------------------------------------------------------------------------

  Future<StoredOrder?> getOrder(String poNumber) async {
    final r = await _db.query('purchase_orders', where: 'po_number = ?', whereArgs: [poNumber]);
    return r.isEmpty ? null : _toStored(r.first);
  }

  Future<List<StoredOrder>> listOrders({int limit = 500}) async {
    final r = await _db.query('purchase_orders', orderBy: 'imported_at DESC', limit: limit);
    return r.map(_toStored).toList();
  }

  Future<List<StoredOrder>> listMemos({int limit = 500}) async {
    final r = await _db.query('purchase_orders', where: 'memo_number IS NOT NULL', orderBy: 'memo_number DESC', limit: limit);
    return r.map(_toStored).toList();
  }

  /// Saves a parsed order. Existing memo bookkeeping for the same PO number
  /// is kept.
  Future<void> saveOrder(PurchaseOrder po, {required String outletDisplayName}) async {
    final existing = await getOrder(po.poNumber);
    await _db.insert(
      'purchase_orders',
      {
        'po_number': po.poNumber,
        'chain': po.chain.id,
        'po_date': po.poDate,
        'outlet_po_name': po.outletName,
        'outlet_display': outletDisplayName,
        'total': po.computedTotal,
        'json': jsonEncode(po.toJson()),
        'imported_at': (existing?.importedAt ?? DateTime.now()).toIso8601String(),
        'memo_number': existing?.memoNumber,
        'supply_date': existing?.supplyDate?.toIso8601String(),
        'memo_path': existing?.memoPath,
        'generated_at': existing?.generatedAt?.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveMemoResult({
    required String poNumber,
    required int memoNumber,
    required DateTime supplyDate,
    required String memoPath,
    required String outletDisplayName,
  }) =>
      _db.update(
        'purchase_orders',
        {
          'memo_number': memoNumber,
          'supply_date': supplyDate.toIso8601String(),
          'memo_path': memoPath,
          'outlet_display': outletDisplayName,
          'generated_at': DateTime.now().toIso8601String(),
        },
        where: 'po_number = ?',
        whereArgs: [poNumber],
      );

  Future<void> deleteOrder(String poNumber) => _db.delete('purchase_orders', where: 'po_number = ?', whereArgs: [poNumber]);

  StoredOrder _toStored(Map<String, Object?> r) => StoredOrder(
        po: PurchaseOrder.fromJson(jsonDecode(r['json'] as String) as Map<String, dynamic>),
        outletDisplayName: r['outlet_display'] as String? ?? '',
        importedAt: DateTime.parse(r['imported_at'] as String),
        memoNumber: r['memo_number'] as int?,
        supplyDate: r['supply_date'] == null ? null : DateTime.parse(r['supply_date'] as String),
        memoPath: r['memo_path'] as String?,
        generatedAt: r['generated_at'] == null ? null : DateTime.parse(r['generated_at'] as String),
      );

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  Future<String?> getSetting(String key) async {
    final r = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) =>
      _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Returns the next memo number and advances the counter, atomically.
  Future<int> takeMemoNumber() => _db.transaction((txn) async {
        final r = await txn.query('settings', where: 'key = ?', whereArgs: ['next_memo_number']);
        final n = r.isEmpty ? 1 : int.tryParse(r.first['value'] as String? ?? '1') ?? 1;
        await txn.insert('settings', {'key': 'next_memo_number', 'value': '${n + 1}'}, conflictAlgorithm: ConflictAlgorithm.replace);
        return n;
      });

  Future<void> close() => _db.close();
}
