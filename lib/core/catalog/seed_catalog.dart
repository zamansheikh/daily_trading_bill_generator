import '../../domain/chain.dart';
import '../../domain/models.dart';
import 'catalog.dart';

/// The catalogue Daily Trading prints on its memos, seeded from the reference
/// memos. Order is the print order. A `null` Best Buy price means the price
/// cell is left blank on Best Buy memos (as on the reference memo), and
/// `bb: false` means the product is not printed on Best Buy memos at all.
class SeedCatalog {
  SeedCatalog._();

  // dtCode, English name, Bangla name, size, Daily Shopping price, on Best Buy memo?, Best Buy price
  static const List<(String, String, String, String, double, bool, double?)> _rows = [
    ('5000000641', 'Ajwain', 'জইন', '50gm', 37.40, true, null),
    ('5000000561', 'Almond', 'কাঠবাদাম', '100gm', 179.40, true, 213.20),
    ('5000000562', 'Almond', 'কাঠবাদাম', '50gm', 93.15, true, 95.85),
    ('5000000563', 'Alubokhara', 'আলুবোখারা', '100gm', 179.40, true, 195.00),
    ('5000000564', 'Alubokhara', 'আলুবোখারা', '50gm', 91.80, true, 95.85),
    // The buyer's POs carry 5000000628 for 200gm and 5000000627 for 100gm;
    // the old Excel template had these two codes swapped.
    ('5000000628', 'Araroot', 'এ্যারারুট', '200gm', 29.70, true, null),
    ('5000000627', 'Araroot', 'এ্যারারুট', '100gm', 16.50, true, null),
    ('5000000602', 'Bit Salt', 'বিট লবণ', '100gm', 26.40, true, null),
    ('5000000625', 'Bit Salt', 'বিট লবণ', '50gm', 17.00, true, null),
    ('5000000632', 'Black Cardamom', 'কালো এলাচ', '25gm', 122.40, true, null),
    ('5000000565', 'Black Cumin', 'কালোজিরা', '50gm', 34.50, true, 33.75),
    ('5000000603', 'Black pepper', 'কালো গোলমরিচ', '50gm', 85.80, true, 93.60),
    ('5000000604', 'Black pepper', 'কালো গোলমরিচ', '25gm', 46.20, true, 51.80),
    ('5000000951', 'Botam Papor', 'বোতাম পাপড়', '200gm', 35.75, false, null),
    ('5000000606', 'Caraway Seeds', 'শাহী জিরা', '25gm', 40.20, true, 43.20),
    ('5000000568', 'Cardamom', 'এলাচ', '50gm', 300.20, true, 319.95),
    ('5000000567', 'Cardamom', 'এলাচ', '25gm', 155.80, true, 166.05),
    ('5000000629', 'Cashew Nut', 'কাজুবাদাম', '100gm', 210.45, true, 237.90),
    ('5000000569', 'Cashew Nut', 'কাজুবাদাম', '50gm', 110.40, true, 124.80),
    ('5000000601', 'Chaina Grass', 'চায়না গ্রাস', '5gm', 25.20, true, 26.95),
    ('5000000072', 'Chia Seed', 'চিয়া বীজ', '50gm', 39.60, true, null),
    ('5000000597', 'Chik peas flour', 'বুট বেসন', '500gm', 61.20, true, null),
    ('5000000950', 'Chinese Papor', 'চাইনিজ পাঁপড়', '200gm', 35.75, false, null),
    ('5000000571', 'Cinnamon', 'দারুচিনি', '50gm', 32.85, true, 35.10),
    ('5000000570', 'Cinnamon', 'দারুচিনি', '100gm', 62.05, true, 66.30),
    ('5000000573', 'Clove', 'লবঙ্গ', '50gm', 110.25, true, 122.50),
    ('5000000572', 'Clove', 'লবঙ্গ', '25gm', 56.70, true, 63.00),
    ('5000000617', 'Coriander Whole', 'আস্ত ধনিয়া', '100gm', 35.20, true, 38.50),
    ('5000000577', 'Cumin', 'জিরা', '500gm', 414.80, true, null),
    ('5000000575', 'Cumin', 'জিরা', '200gm', 163.20, true, 170.40),
    ('5000000574', 'Cumin', 'জিরা', '100gm', 88.40, true, 97.50),
    ('5000000576', 'Cumin', 'জিরা', '50gm', 47.60, true, 49.70),
    ('5000000580', 'Dried Chilies', 'শুকনা মরিচ', '100gm', 51.00, true, 56.25),
    ('5000000578', 'Dried Grapes', 'কিসমিস', '100gm', 115.60, true, 127.50),
    ('5000000579', 'Dried Grapes', 'কিসমিস', '50gm', 61.20, true, 67.50),
    ('5000000610', 'Edible soda', 'খাবার সোডা', '100gm', 16.50, true, 18.25),
    ('5000000649', 'Fennel', 'মিষ্টি জিরা', '100gm', 47.60, true, null),
    ('5000000648', 'Fennel', 'মিষ্টি জিরা', '50gm', 27.20, true, null),
    ('5000000609', 'Ground Black pepper', 'কালো গোলমরিচ গুড়া', '50gm', 94.50, true, 98.55),
    ('5000000608', 'Ground Cardamom', 'এলাচ গুড়া', '20gm', 154.44, true, 158.40),
    ('5000000600', 'Ground Cinnamon', 'দারুচিনি গুড়া', '50gm', 34.00, true, 37.50),
    ('5000000607', 'Ground Garam mashala', 'গরম মসলা গুড়া', '50gm', 51.00, true, 56.25),
    ('5000000633', 'Ground Mace', 'জয়ত্রী গুড়া', '20gm', 95.20, true, 105.00),
    ('5000000634', 'Ground Mathi', 'মেথি গুড়া', '80gm', 27.20, true, null),
    ('5000000599', 'Ground Nutmeg', 'জায়ফল গুড়া', '20gm', 36.30, true, 39.60),
    ('5000000639', 'Ground White Pepper', 'সাদা গোল মরিচ গুড়া', '50gm', 88.40, true, null),
    ('3000000568', 'Isobgul Bhushi', 'ইসবগুল ভুসি', '50gm', 108.80, true, null),
    ('5000000952', 'Kacha Fhuchka', 'কাঁচা ফুচকা', '200gm', 91.00, false, null),
    ('5000000949', 'Love Papor', 'লাভ পাপড়', '200gm', 35.75, false, null),
    ('5000000618', 'Mace', 'জয়ত্রী', '20gm', 89.70, true, 97.50),
    ('5000000613', 'Mathi', 'মেথি', '100gm', 23.80, true, 26.25),
    ('5000000581', 'Mixed Fruits', 'মিক্সড ফ্রুট', '100gm', 88.40, true, 97.50),
    ('5000000619', 'Nutmeg', 'জায়ফল', '50gm', 71.50, true, 80.30),
    ('5000000611', 'Nutmeg', 'জায়ফল', '25gm', 35.75, true, 40.70),
    ('5000000616', 'Panchforn', 'পাঁচফোড়ন', '100gm', 40.80, true, 45.00),
    ('5000000948', 'Pasta Papor', 'পাস্তা পাপড়', '200gm', 40.30, false, null),
    ('5000000582', 'Peanut Fried', 'চিনাবাদাম ভাজা', '100gm', 40.80, true, 45.00),
    ('5000000584', 'Pistachio', 'পেস্তা বাদাম', '50gm', 234.60, true, 255.00),
    ('5000000583', 'Pistachio', 'পেস্তা বাদাম', '25gm', 124.20, true, 135.00),
    ('5000000631', 'Poppy seed', 'পোস্তদানা', '25gm', 71.40, true, 78.75),
    ('5000000630', 'Red Mustard', 'লাল সরিষা', '100gm', 20.70, true, null),
    ('5000000596', 'Rice Flour', 'চালের গুড়া', '1KG', 89.70, true, null),
    ('5000000900', 'Sagudana', 'সাগুদানা', '1kg', 210.00, true, null),
    ('5000000899', 'Sagudana', 'সাগুদানা', '500gm', 120.90, true, null),
    ('5000000626', 'Sagudana', 'সাগুদানা', '100gm', 27.00, true, 30.00),
    ('5000000386', 'Star Masala', 'স্টার মসলা', '50gm', 95.20, true, null),
    ('5000000947', 'Star Papor', 'স্টার পাপড়', '200gm', 35.75, false, null),
    ('5000000620', 'Suger Candy', 'তালমিছরি', '200gm', 47.60, true, 52.50),
    ('5000000622', 'Tamarind', 'তেঁতুল', '200gm', 48.30, true, null),
    ('5000000585', 'Tejpata', 'তেজপাতা', '50gm', 17.25, true, 18.75),
    ('5000000624', 'Testing Salt', 'স্বাদ লবণ', '100gm', 35.75, true, 39.05),
    ('5000000605', 'Testing Salt', 'স্বাদ লবণ', '50gm', 20.10, true, 21.90),
    ('5000000598', 'Tokma', 'তোকমা', '50gm', 16.50, true, 18.25),
    ('5000000953', 'Walnut', 'আখরোট', '100gm', 182.00, false, null),
    ('5000000612', 'White Pepper', 'সাদা গোল মরিচ', '25gm', 47.60, true, 52.50),
    ('5000000614', 'White Sesame', 'সাদা তিল', '100gm', 54.40, true, null),
    ('5000000623', 'Yeast Bottle', 'ইস্ট', '20gm', 27.20, true, 30.00),
    ('5000000621', 'Yellow Mustard', 'হলুদ সরিষা', '100gm', 20.70, true, 22.50),
  ];

  /// Best Buy's own 6-digit codes, learned from the reference orders.
  static const Map<String, String> bestBuyAliases = {
    '895672': '5000000561', '895195': '5000000562', '895683': '5000000564',
    '895677': '5000000565', '895698': '5000000603', '895690': '5000000604',
    '895335': '5000000606', '895678': '5000000568', '895197': '5000000567',
    '895686': '5000000629', '895669': '5000000569', '895674': '5000000571',
    '895673': '5000000570', '895689': '5000000573', '895679': '5000000572',
    '895676': '5000000574', '895681': '5000000575', '895675': '5000000576',
    '895671': '5000000580', '895199': '5000000578', '895196': '5000000579',
    '895334': '5000000610', '895691': '5000000618', '895707': '5000000613',
    '895693': '5000000611', '895684': '5000000616', '895194': '5000000582',
    '895687': '5000000631', '895338': '5000000626', '895670': '5000000585',
    '895327': '5000000598',
  };

  static Catalog build() {
    final products = <Product>[];
    final chainProducts = <ChainProduct>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final id = i + 1;
      products.add(Product(id: id, dtCode: r.$1, nameEn: r.$2, nameBn: r.$3, size: r.$4, sortOrder: (i + 1) * 10));
      chainProducts.add(ChainProduct(chain: Chain.dailyShopping, productId: id, included: true, price: r.$5));
      chainProducts.add(ChainProduct(chain: Chain.bestBuy, productId: id, included: r.$6, price: r.$7));
    }
    final byCode = {for (final p in products) p.dtCode: p.id};
    final aliases = <(Chain, String, int)>[
      for (final e in bestBuyAliases.entries) (Chain.bestBuy, e.key, byCode[e.value]!),
    ];
    return Catalog(products: products, chainProducts: chainProducts, aliases: aliases);
  }
}
