import 'dart:math';

import '../../domain/chain.dart';
import '../../domain/models.dart';
import 'catalog.dart';

/// How a PO line was matched to the catalogue.
enum MatchKind { code, name, none }

class ProductMatch {
  ProductMatch(this.product, this.kind, this.score);
  final Product? product;
  final MatchKind kind;
  final double score;
}

/// Matches purchase order lines to catalogue products.
///
/// Order of preference: the buyer's product code (Daily Trading's own code or
/// a learned alias), then a normalised name plus size comparison. Name
/// matching is needed because Best Buy uses its own codes and both chains
/// spell product names inconsistently ("Cashew" / "Cashew Nut", "Testing
/// Solt" / "Tasting Salt", "Chick-Peas flour" / "Chik peas flour").
class ProductMatcher {
  ProductMatcher(this.catalog);
  final Catalog catalog;

  /// Minimum similarity for a name match to be accepted.
  static const double threshold = 0.6;

  ProductMatch match(Chain chain, PoItem item) {
    final byCode = catalog.byBuyerCode(chain, item.code);
    if (byCode != null) return ProductMatch(byCode, MatchKind.code, 1);
    return matchByName(item.name);
  }

  /// Best candidate even when it is below [threshold]; used for suggestions.
  ProductMatch bestCandidate(String rawName) => _matchByName(rawName, minScore: 0.2);

  ProductMatch matchByName(String rawName) => _matchByName(rawName, minScore: threshold);

  ProductMatch _matchByName(String rawName, {required double minScore}) {
    final size = normalizeSize(extractSize(rawName));
    final tokens = normalizeName(rawName);
    Product? best;
    var bestScore = 0.0;
    var ties = 0;
    for (final p in catalog.products) {
      if (!p.active) continue;
      // A PO name without a size ("Yeast Bottle") may match a product of any
      // size, but only when that leaves a single best candidate.
      if (size.isNotEmpty && normalizeSize(p.size) != size) continue;
      final pTokens = normalizeName('${p.nameEn} ${p.size}');
      // Token overlap catches word-order and synonym differences; character
      // bigrams catch typos such as "Cardamon" / "Cardamom".
      final s = max(_dice(tokens, pTokens), _bigramDice(tokens.join(' '), pTokens.join(' ')));
      if (s > bestScore) {
        bestScore = s;
        best = p;
        ties = 0;
      } else if (s == bestScore && s > 0) {
        ties++;
      }
    }
    if (best != null && bestScore >= minScore && (size.isNotEmpty || ties == 0)) {
      return ProductMatch(best, MatchKind.name, bestScore);
    }
    return ProductMatch(null, MatchKind.none, bestScore);
  }

  // ---------------------------------------------------------------------------
  // Normalisation
  // ---------------------------------------------------------------------------

  static final _sizeRe = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|gm|g|ml|l|ltr|pcs|pc)\b', caseSensitive: false);

  /// "Daily Shopping Mathi 100 gm" -> "100 gm"; '' when absent.
  static String extractSize(String name) => _sizeRe.firstMatch(name)?.group(0) ?? '';

  /// "100 gm", "100g", "1Kg", "1KG" -> "100gm", "100gm", "1kg", "1kg".
  static String normalizeSize(String s) {
    final m = _sizeRe.firstMatch(s);
    if (m == null) return s.toLowerCase().replaceAll(' ', '');
    var unit = m.group(2)!.toLowerCase();
    if (unit == 'g') unit = 'gm';
    if (unit == 'ltr') unit = 'l';
    if (unit == 'pcs') unit = 'pc';
    return '${m.group(1)}$unit';
  }

  static const _tokenSynonyms = {
    'chines': 'chinese',
    'china': 'chaina',
    'fenugreek': 'mathi',
    'masala': 'mashala',
    'tasting': 'testing',
    'solt': 'salt',
    'chick': 'chik',
    'chickpeas': 'chik peas',
    'sugar': 'suger',
    'raisin': 'dried grapes',
    'kishmish': 'dried grapes',
    'bayleaf': 'tejpata',
    'isabgol': 'isobgul',
    'ispaghula': 'isobgul',
  };

  static const _dropTokens = {'daily', 'shopping', 'bran', 'white', 'piece', 'pcs', 'pc', 'gm', 'g', 'kg', 'whole'};

  /// Lower-cased, size-free, punctuation-free, synonym-mapped token set.
  static Set<String> normalizeName(String name) {
    var s = name.toLowerCase();
    s = s.replaceAll(_sizeRe, ' ');
    s = s.replaceAll(RegExp(r'[^a-z\s]'), ' ');
    final out = <String>{};
    for (var t in s.split(RegExp(r'\s+'))) {
      if (t.isEmpty) continue;
      t = _tokenSynonyms[t] ?? t;
      for (final part in t.split(' ')) {
        if (part.isEmpty || _dropTokens.contains(part)) continue;
        out.add(part);
      }
    }
    // "Coriander whole" and "Peanut Fried (White)" reduce to their head words,
    // which is what the catalogue also reduces to.
    return out;
  }

  static double _bigramDice(String a, String b) {
    Set<String> grams(String s) => {for (var i = 0; i + 1 < s.length; i++) s.substring(i, i + 2)};
    return _dice(grams(a), grams(b));
  }

  static double _dice(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final inter = a.intersection(b).length;
    return 2 * inter / (a.length + b.length);
  }
}
