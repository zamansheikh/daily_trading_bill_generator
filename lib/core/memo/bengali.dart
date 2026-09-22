/// Bengali numeral helpers.
const _bn = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

/// "12" -> "১২". Non-digits pass through.
String toBengaliDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x30 && r <= 0x39) {
      b.write(_bn[r - 0x30]);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}
