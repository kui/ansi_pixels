library ansi_pixels.rgb_picker;

import 'dart:html';

/// see http://www.w3.org/TR/AERT#color-contrast
class Rgba {
  static const BRIGHTNESS_THRESHOLD = 125;
  static const CANVAS_WIDTH = 1,
      CANVAS_HEIGHT = 1;

  final int red, green, blue, alpha;
  final int brightness;

  Rgba(int red, int green, int blue, int alpha)
      : this.red = red,
        this.green = green,
        this.blue = blue,
        this.alpha = alpha,
        this.brightness = ((red * 299 + green * 587 + blue * 114) / 1000)
            .round();

  factory Rgba.fromColorString(String color) {
    final ctx = _createContext();
    _putColor(ctx, color);
    final d = ctx.getImageData(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT).data;
    return new Rgba(d[0], d[1], d[2], d[3]);
  }

  static CanvasRenderingContext2D _createContext() {
    final canvas =
        new CanvasElement(width: CANVAS_WIDTH, height: CANVAS_HEIGHT);
    return canvas.getContext('2d');
  }

  Rgba putColor(Rgba rgba) {
    final ctx = _createContext();
    _putColor(ctx, toColorString());
    _putColor(ctx, rgba.toColorString());
    final d = ctx.getImageData(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT).data;
    return new Rgba(d[0], d[1], d[2], d[3]);
  }

  static _putColor(CanvasRenderingContext2D ctx, String color) {
    ctx
      ..fillStyle = color
      ..fillRect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);
  }

  Rgba chooseColor(Iterable<Rgba> rgbas) => rgbas
      .where((r) => (r.brightness - brightness).abs() > BRIGHTNESS_THRESHOLD)
      .fold(null, (Rgba prev, Rgba r) =>
          (prev != null && r.brightness > prev.brightness) ? prev : r);

  @override
  toString() => toColorString();
  toColorString() => 'rgba($red, $green, $blue, ${alpha / 255})';
}
