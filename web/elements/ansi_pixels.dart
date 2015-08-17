import 'dart:html';
import 'dart:convert';
import 'dart:async';
import 'package:ansi_pixels/rgba.dart';
import 'package:ansi_pixels/ansi_pixels.dart';
import 'package:ansi_pixels/base64_zip.dart';
import 'package:polymer/polymer.dart';
import 'package:pixel_canvas/pixel_canvas.dart';
import 'package:fold_button/fold_button.dart';
import 'package:ansi_color_palette/ansi_color_palette.dart';
import 'package:ansi_color_palette/ansi_color_code.dart';

@CustomTag('ansi-pixels')
class AnsiPixelsElement extends PolymerElement {
  static const int DEFAULT_PIXELS = 16;
  static const int DEFAULT_PIXEL_SIZE = 25;
  static const ZIPPED_JSON_UPDATE_DELAY = const Duration(seconds: 1);
  static const SCRIPT_URL =
      'https://raw.githubusercontent.com/kui/ansi_pixels/master/tool/ansi-pixels.py';
  static const SHARE_LINK = 'http://ansipixels.k-ui.jp/%s.html';
  static const ANSI_TEXT_URL = 'http://ansipixels.k-ui.jp/%s';
  static final Rgba lightGridColor = new Rgba(255, 255, 255, 127);
  static final Rgba darkGridColor = new Rgba(0, 0, 0, 127);
  static final Rgba baseBgColor = new Rgba(240, 240, 240, 255);

  // settings
  @observable int hpixels = DEFAULT_PIXELS;
  @observable int vpixels = DEFAULT_PIXELS;
  @observable int pixelSize = DEFAULT_PIXEL_SIZE;
  @observable String fgColor = 'White';
  @observable String bgColor = 'RGBA(0, 0, 0, 0.8)';
  @observable bool nogrids = false;
  @observable String colorSpace = '8';

  @reflectable
  AnsiColorCode get drawingColorCode =>
      _palette == null ? null : _palette.ansiCode;
  @reflectable
  bool get hasSelection =>
      canvas != null && _haveSelection(canvas.currentAction);
  @reflectable
  bool get hasFloatLayer =>
      canvas != null && _haveFloatLayer(canvas.currentAction);
  @reflectable
  bool get hasOutline => hasSelection || hasFloatLayer;
  @reflectable
  bool get isPixelPickingAction =>
      canvas != null && canvas.currentAction is PixelPickingAction;

  @observable String selectionContext;
  @observable String zippedJson;
  @observable String currentActionName;
  @observable String gridColor = lightGridColor.toColorString();
  @observable String ansiTextUrl;
  @observable String shareLink;
  @observable ObservableMap commands = toObservable({'script': true});
  @observable String pythonArgs;
  @observable bool isStackingHistory = false;

  Timer zippedJsonUpdater;
  Function afterRendered;

  PixelCanvasElement get canvas => shadowRoot.querySelector('pixel-canvas');
  AnsiColorPaletteElement get _palette =>
      shadowRoot.querySelector('ansi-color-palette');
  FoldButtonElement get _settingFoldButton =>
      shadowRoot.querySelector('fold-button[target="#settings"]');
  ElementList get _bgColorTarget =>
      shadowRoot.querySelectorAll('#bgcolor-container');
  ElementList get _fgColorTarget =>
      shadowRoot.querySelectorAll('#console,#samples');

  AnsiPixelsElement.created() : super.created();

  @override
  domReady() {
    super.domReady();
  }

  @override
  attached() {
    super.attached();
    fgColorChanged();
    bgColorChanged();
    _initCallbacks();
    _startUrlFragmentObsevation();
    async((_) {
      _updateZipped();
    });
    _initLocalStorageProps();
  }

  void _initLocalStorageProps() {
    final saved = window.localStorage['commands'];
    if (saved != null) {
      print('load command: $saved');
      commands.keys.forEach((k) => commands[k] = (k == saved));
      commands[saved] = true;
    }
    onPropertyChange(commands, #values, () {
      window.localStorage['commands'] =
          commands.keys.firstWhere((k) => commands[k]);
    });

    final isStacked = window.localStorage['isStackingHistory'];
    if (isStacked != null) {
      print('load isStackingHistory: $isStacked');
      isStackingHistory = (isStacked == 'true');
    }
    onPropertyChange(this, #isStackingHistory, () {
      window.localStorage['isStackingHistory'] = isStackingHistory.toString();
    });
  }

  void _startUrlFragmentObsevation() {
    window.onPopState.listen((_) {
      _loadZippedJsonFromHashFragment(window.location.hash);
    });

    _loadZippedJsonFromHashFragment(window.location.hash, true);
  }

  void _loadZippedJsonFromHashFragment(String hash,
      [bool updateZippedJson = false]) {
    if (hash == null) return;

    final zipped = (hash.startsWith('#')) ? hash.substring(1) : hash;
    if (zipped.isEmpty) return;
    if (zipped == zippedJson) return;

    print('load from the URL fragment');
    _loadZippedJson(zipped, updateZippedJson);
  }

  void _loadZippedJson(String zipped, bool updateZippedJson) {
    final j = JSON.decode(unzip(zipped));
    if (j is! Map) {
      window.console.warn('Unexpected json format: ' + j.runtimeType);
      return;
    }

    pixelSize = j['pixelSize'];
    bgColor = j['bgColor'];
    fgColor = j['fgColor'];
    colorSpace = j['colorSpace'];
    nogrids = j['nogrids'];
    _loadPixels(j['pixels'], updateZippedJson);
    canvas.render();

    zippedJson = zipped;
    _updateAnsiTextUrl();
    _updateShareLink();
    _updatePythonArgs();
  }

  void _loadPixels(List<List<int>> pixels, bool updateZippedJson) {
    if (pixels == null || pixels.isEmpty) return;

    vpixels = pixels.length;
    hpixels = pixels.first.length;
    canvas.pixels.eachColorWithIndex((color, x, y) {
      canvas.setColor(x, y, null);
    });

    afterRendered = () {
      new AnsiPixels.fromJson(pixels).forEach((x, y, code) {
        final String color = (code == null) ? null : getColorFromAnsiCode(code);
        canvas.setColor(x, y, color);
      });
      afterRendered = null;
      if (!updateZippedJson)
          // canncel zippedJson update because the browser history go forward
          new Timer(
              ZIPPED_JSON_UPDATE_DELAY * 0.9, () => _clearZippedJsonUpdater());
    };
  }

  void _initCallbacks() {
    canvas.drawingColor = getColorFromAnsiCode(0);
    _palette.selectByCodeInt(0);

    _palette.onColorChange.listen((e) {
      canvas.currentAction = null;
      canvas.drawingColor = e.newColor;
      notifyPropertyChange(#drawingColorCode, e.oldCode, e.newCode);
      currentActionName = _getCurrentActionName(canvas.currentAction);
    });
    canvas.onActionChange.listen((e) {
      final oldHasSelection = _haveSelection(e.oldAction);
      final oldHasFloatLayer = _haveFloatLayer(e.oldAction);
      notifyPropertyChange(#hasSelection, oldHasSelection, hasSelection);
      notifyPropertyChange(#hasFloatLayer, oldHasFloatLayer, hasFloatLayer);
      notifyPropertyChange(
          #hasOutline, oldHasSelection || oldHasFloatLayer, hasOutline);
      final oldIsPixelPickingAction = e.oldAction is PixelPickingAction;
      notifyPropertyChange(
          #isPixelPickingAction, oldIsPixelPickingAction, isPixelPickingAction);

      currentActionName = _getCurrentActionName(e.newAction);
    });
    currentActionName = _getCurrentActionName(canvas.currentAction);

    canvas.onPixelColorChange.listen((_) {
      _delayUpdateZipped();
    });
    canvas.onAfterRendering.listen((_) {
      if (afterRendered == null) return;
      afterRendered();
    });
  }

  String _getCurrentActionName(Action a) {
    if (a is DrawingAction) {
      return (drawingColorCode == null)
          ? 'Erase'
          : 'Drawing with code:${drawingColorCode.code}';
    } else if (a is SameColorsSelectionAction) {
      return 'Select all same colors';
    } else if (a is SameColorNeighborsSelectionAction) {
      return 'Select same color neighbors';
    } else if (a is RectangleSelectionAction) {
      return 'Select as a rectangle';
    } else if (a is InstantSelectionAction) {
      return 'Select as drawing';
    } else if (a is FloatLayerAction) {
      return 'Move/paste/delete the float-layer';
    } else if (a is PixelPickingAction) {
      return 'Pick a color';
    } else {
      window.console.warn('Unknown action: ${a.runtimeType}');
      return '-';
    }
  }

  hpixelsChanged() {
    _delayUpdateZipped();
  }
  vpixelsChanged() {
    _delayUpdateZipped();
  }
  pixelSizeChanged() {
    _delayUpdateZipped();
  }

  nogridsChanged() {
    _delayUpdateZipped();
  }

  colorSpaceChanged() {
    _delayUpdateZipped();
  }

  fgColorChanged() {
    _fgColorTarget.forEach((Element e) => e.style.color = fgColor);
  }

  bgColorChanged() {
    _bgColorTarget.forEach((Element e) => e.style.backgroundColor = bgColor);
    _changeGridColor();
  }

  void _changeGridColor() {
    final bg = new Rgba.fromColorString(bgColor);
    final r = baseBgColor.putColor(bg);
    final newColor = r.chooseColor([lightGridColor, darkGridColor]);
    if (newColor != null) gridColor = newColor.toColorString();
  }

  void _delayUpdateZipped() {
    _clearZippedJsonUpdater();
    zippedJsonUpdater = new Timer(ZIPPED_JSON_UPDATE_DELAY, () {
      _updateZipped();
    });
  }

  void _updateZipped() {
    _clearZippedJsonUpdater();

    final newZippedJson = toZippedJson();
    if (newZippedJson == null) return;
    if (newZippedJson == zippedJson) return;

    zippedJson = newZippedJson;
    _updateAnsiTextUrl();
    _updateShareLink();
    _updatePythonArgs();
    _updateHistory();
  }

  void _clearZippedJsonUpdater() {
    if (zippedJsonUpdater == null) return;
    zippedJsonUpdater.cancel();
    zippedJsonUpdater = null;
  }

  void _updateAnsiTextUrl() {
    ansiTextUrl = ANSI_TEXT_URL.replaceFirst('%s', zippedJson);
  }

  void _updateShareLink() {
    shareLink = SHARE_LINK.replaceFirst('%s', zippedJson);
  }

  void _updatePythonArgs() {
    pythonArgs = '-c "\$(curl -s $SCRIPT_URL)" "$zippedJson"';
  }

  void _updateHistory() {
    final uri = Uri.parse(window.location.href);
    final newUri = new Uri(
        fragment: zippedJson,
        query: uri.query,
        host: uri.host,
        path: uri.path,
        port: uri.port,
        scheme: uri.scheme,
        userInfo: uri.userInfo);

    final hash = window.location.hash;
    if (isStackingHistory && hash != null && hash.isNotEmpty) {
      window.history.pushState(null, 'ANSI Pixels', newUri.toString());
    } else {
      window.history.replaceState(null, 'ANSI Pixels', newUri.toString());
    }
  }

  // elements events

  void changeColorSpace(Event e, _, InputElement target) {
    colorSpace = target.value;
  }

  void deselectColor() {
    canvas.drawingColor = null;
    _palette.selectedCell = null;
  }

  void downloadAsPng() => canvas.downloadAs('ansi-pixels.png');

  void foldAll(MouseEvent e) {
    _settingFoldButton.fold();
  }

  void stopPropagation(MouseEvent e) => e.stopPropagation();

  void cancelAction() => canvas.currentAction = null;

  void delete() {
    if (hasFloatLayer) {
      canvas.deleteFloatLayer();
    } else if (hasSelection) {
      canvas.deleteSelection();
    }
  }

  void selectInputAllText(Event e, _, Element target) {
    _updateZipped();

    InputElement input = target;
    async((_) => input.setSelectionRange(0, input.value.length, 'backward'));
  }

  void pickColor() {
    canvas.pickPixel().then((pixel) {
      final int code = getAnsiCodeFromColor(pixel.color);
      if (code != null) {
        if (colorSpace == '8') {
          if (code > 16) {
            colorSpace = '256';
          } else if (code > 8) {
            colorSpace = '16';
          }
        } else if (colorSpace == '16') {
          if (code > 16) {
            colorSpace = '256';
          }
        }
      }
      async((_) {
        if (code == null) {
          deselectColor();
        } else {
          _palette.selectByCodeInt(code);
        }
      });
    });
  }

  Map toJson() => {
    'pixelSize': pixelSize,
    'bgColor': bgColor,
    'fgColor': fgColor,
    'colorSpace': colorSpace,
    'nogrids': nogrids,
    'pixels': _generateAnsiPixels()
  };

  AnsiPixels _generateAnsiPixels() => new AnsiPixels.generate(hpixels, vpixels,
      (int x, int y) {
    final color = canvas.getColor(x, y);
    final code = getAnsiCodeFromColor(color);
    return code;
  });

  Object toZippedJson() => zip(JSON.encode(this), urlSafe: true);
}

bool _haveSelection(Action a) =>
    a is SelectionAction && a.bounds.points.isNotEmpty;
bool _haveFloatLayer(Action a) =>
    a is FloatLayerAction && a.floatLayer.points.isNotEmpty;
