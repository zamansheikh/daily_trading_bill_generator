// Draws the app icon (a receipt on a green tile) as a 1024x1024 PNG.
// Run:  dart run tool/make_icon.dart
import 'dart:io';


import 'package:image/image.dart' as img;

void main() {
  const size = 1024;
  final icon = img.Image(width: size, height: size, numChannels: 4);
  img.fill(icon, color: img.ColorRgba8(0, 0, 0, 0));

  // Green rounded tile.
  final green = img.ColorRgb8(27, 94, 32);
  final greenLight = img.ColorRgb8(46, 125, 50);
  _roundedRect(icon, 0, 0, size, size, 220, green);
  // Soft top-left highlight.
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final p = icon.getPixel(x, y);
      if (p.a == 0) continue;
      final t = ((x + y) / (2 * size)).clamp(0.0, 1.0);
      icon.setPixelRgba(
        x,
        y,
        (greenLight.r * (1 - t) + green.r * t).round(),
        (greenLight.g * (1 - t) + green.g * t).round(),
        (greenLight.b * (1 - t) + green.b * t).round(),
        255,
      );
    }
  }

  // Receipt: white sheet with a zig-zag bottom edge and a folded corner.
  final white = img.ColorRgb8(255, 255, 255);
  const left = 262, top = 190, right = 762, bottom = 800;
  img.fillRect(icon, x1: left, y1: top, x2: right, y2: bottom, color: white);
  // Zig-zag along the bottom.
  const tooth = 50;
  for (var x = left; x < right; x += tooth) {
    final tri = [img.Point(x, bottom), img.Point(x + tooth ~/ 2, bottom + 36), img.Point(x + tooth, bottom)];
    img.fillPolygon(icon, vertices: tri, color: white);
  }
  // Shadow under the sheet.
  _roundedRect(icon, left + 10, bottom + 30, right - left, 22, 8, img.ColorRgba8(0, 0, 0, 40));
  img.fillRect(icon, x1: left, y1: top, x2: right, y2: bottom, color: white);
  for (var x = left; x < right; x += tooth) {
    final tri = [img.Point(x, bottom), img.Point(x + tooth ~/ 2, bottom + 36), img.Point(x + tooth, bottom)];
    img.fillPolygon(icon, vertices: tri, color: white);
  }

  // Header bar + text lines in dark grey; a green total line at the bottom.
  final ink = img.ColorRgb8(55, 65, 60);
  final soft = img.ColorRgb8(170, 180, 175);
  _roundedRect(icon, left + 60, top + 60, 380, 44, 22, ink);
  for (var i = 0; i < 4; i++) {
    final y = top + 170 + i * 82;
    _roundedRect(icon, left + 60, y, 250, 30, 15, soft);
    _roundedRect(icon, right - 60 - 110, y, 110, 30, 15, soft);
  }
  _roundedRect(icon, left + 60, bottom - 130, 380, 6, 3, soft);
  _roundedRect(icon, left + 60, bottom - 100, 170, 40, 20, ink);
  _roundedRect(icon, right - 60 - 150, bottom - 100, 150, 40, 20, greenLight);

  File('assets/icon/app_icon.png').writeAsBytesSync(img.encodePng(icon));
  // Foreground for Android adaptive icons: same receipt, transparent tile.
  final fg = img.Image(width: size, height: size, numChannels: 4);
  img.fill(fg, color: img.ColorRgba8(0, 0, 0, 0));
  final scaled = img.copyResize(icon, width: 720, height: 720);
  for (var y = 0; y < 720; y++) {
    for (var x = 0; x < 720; x++) {
      final p = scaled.getPixel(x, y);
      // Keep only the sheet (non-green pixels) for the foreground layer.
      final isGreen = p.g > p.r + 20 && p.g > p.b + 20 && p.r < 120;
      if (p.a == 0 || isGreen) continue;
      fg.setPixelRgba(152 + x, 152 + y, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
    }
  }
  File('assets/icon/app_icon_foreground.png').writeAsBytesSync(img.encodePng(fg));
  stdout.writeln('wrote assets/icon/app_icon.png and app_icon_foreground.png');
}

void _roundedRect(img.Image im, int x, int y, int w, int h, int r, img.Color c) {
  img.fillRect(im, x1: x, y1: y, x2: x + w - 1, y2: y + h - 1, color: c, radius: r.toDouble());
}
