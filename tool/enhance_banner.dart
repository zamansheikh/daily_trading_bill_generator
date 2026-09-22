// Cleans up the letterhead scan used on memos:
// trims blank margins, turns the grey JPEG haze into pure white, deepens the
// blacks, upscales 2x and sharpens.  Run:  dart run tool/enhance_banner.dart
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final src = img.decodeImage(File('assets/images/memo_banner_original.png').readAsBytesSync())!;
  var im = img.grayscale(src);

  // 1. Trim margins: keep the bounding box of anything darker than near-white.
  int top = im.height, bottom = 0, left = im.width, right = 0;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (im.getPixel(x, y).r < 200) {
        if (y < top) top = y;
        if (y > bottom) bottom = y;
        if (x < left) left = x;
        if (x > right) right = x;
      }
    }
  }
  const pad = 6;
  left = (left - pad).clamp(0, im.width - 1);
  right = (right + pad).clamp(0, im.width - 1);
  top = (top - pad).clamp(0, im.height - 1);
  bottom = (bottom + pad).clamp(0, im.height - 1);
  im = img.copyCrop(im, x: left, y: top, width: right - left + 1, height: bottom - top + 1);

  // 2. Upscale 2x with cubic interpolation before cleaning, so edges stay smooth.
  im = img.copyResize(im, width: im.width * 2, height: im.height * 2, interpolation: img.Interpolation.cubic);

  // 3. Levels: everything lighter than 225 becomes white, darker than 60 becomes
  //    black, the rest is stretched between. Removes the grey haze.
  for (final p in im) {
    final v = p.r.toDouble();
    final out = v >= 225 ? 255.0 : (v <= 60 ? 0.0 : (v - 60) / (225 - 60) * 255);
    p.r = out.round();
    p.g = out.round();
    p.b = out.round();
  }

  // 4. Gentle unsharp mask.
  final blurred = img.gaussianBlur(im.clone(), radius: 2);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final o = im.getPixel(x, y).r.toDouble();
      final b = blurred.getPixel(x, y).r.toDouble();
      final v = (o + (o - b) * 0.6).clamp(0, 255).round();
      im.setPixelRgb(x, y, v, v, v);
    }
  }

  File('assets/images/memo_banner.png').writeAsBytesSync(img.encodePng(im, level: 9));
  stdout.writeln('cropped to ${right - left + 1}x${bottom - top + 1}, wrote ${im.width}x${im.height} assets/images/memo_banner.png');
}
