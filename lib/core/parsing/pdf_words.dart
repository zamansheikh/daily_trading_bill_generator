import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// A word on a PDF page with its bounding box in PDF points.
class Word {
  Word(this.text, this.left, this.top, this.right, this.bottom);
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  @override
  String toString() => '$text@(${left.toStringAsFixed(0)},${top.toStringAsFixed(0)})';
}

/// All words on one page.
class PageWords {
  PageWords({required this.pageNumber, required this.words, required this.width, required this.height});

  /// 1-based page number.
  final int pageNumber;
  final List<Word> words;
  final double width;
  final double height;
}

/// Extracts positioned words from every page of a PDF.
///
/// This is the only place that touches the PDF library, so the parser itself
/// can be unit tested against plain word lists and the extractor can be
/// swapped without touching parsing logic.
List<PageWords> extractPageWords(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  try {
    final extractor = PdfTextExtractor(doc);
    final pages = <PageWords>[];
    for (var i = 0; i < doc.pages.count; i++) {
      final lines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
      final words = <Word>[];
      for (final line in lines) {
        for (final w in line.wordCollection) {
          final t = w.text.trim();
          if (t.isEmpty) continue;
          final b = w.bounds;
          words.add(Word(t, b.left, b.top, b.right, b.bottom));
        }
      }
      final size = doc.pages[i].size;
      pages.add(PageWords(pageNumber: i + 1, words: words, width: size.width, height: size.height));
    }
    return pages;
  } finally {
    doc.dispose();
  }
}
