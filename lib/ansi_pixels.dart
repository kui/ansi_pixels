library ansi_pixels.ansi_pixels;

import 'package:ansi_color_palette/ansi_color_code.dart';

class AnsiPixels {
  final List<List<int>> _pixels;

  AnsiPixels(int width, int height): _pixels =
      new List.generate(
          height,
          (_) => new List.filled(width, null),
          growable: false);
  factory AnsiPixels.generate(int width, int height, int generateCode(int x, int y)) {
    final p = new AnsiPixels(width, height);
    p.forEach((x, y, code) => p.setCode(x, y, generateCode(x, y)));
    return p;
  }
  factory AnsiPixels.fromAnsiPixels(AnsiPixels origin, int width, int height) =>
      new AnsiPixels.generate(width, height, (int x, int y) {
        try {
          return origin.getCode(x, y);
        } on RangeError {
          return null;
        }
      });
  factory AnsiPixels.fromJson(List<List<int>> j) =>
      new AnsiPixels.generate(j.first.length, j.length, (int x, int y) {
        try {
          final row = j[y];
          return row[x];
        } on RangeError {
          return null;
        }
      });

  int getCode(int x, int y) => _pixels[y][x];
  setCode(int x, int y, int code) { _pixels[y][x] = code; }
  setCodeByColor(int x, int y, String color) {
    setCode(x, y, getAnsiCodeFromColor(color));
  }

  void forEach(void f(int x, int y, int code)) =>
      _matrixIntForEach(_pixels, f);

  toJson() => _pixels;
}

void _matrixIntForEach(List<List<int>> l, void f(int x, int y, int code)) {
  final vlen = l.length;
  final hlen = l.first.length;
  for (int y = 0; y < vlen; y++) {
    final a = l[y];
    for (int x = 0; x < hlen; x++) {
      final code = a[x];
      f(x, y, code);
    }
  }
}
