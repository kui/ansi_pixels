
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
  static final Rgba LIGHT_GRID_COLOR = new Rgba(255, 255, 255, 127);
  static final Rgba DARK_GRID_COLOR = new Rgba(0, 0, 0, 127);
  static final Rgba BASE_BG_COLOR = new Rgba(240, 240, 240, 255);
  static final ZIPPED_JSON_UPDATE_DELAY = new Duration(seconds: 5);
  static final SCRIPT_URL = 'https://raw.githubusercontent.com/kui/ansi_pixels/master/tool/ansi-pixels.py';
  static final SHARE_LINK = 'http://ansipixels.k-ui.jp/%s.html';
  static final ANSI_TEXT_URL = 'http://ansipixels.k-ui.jp/%s';

  // settings
  @published
  String get hpixelsSetting => readValue(#hpixelsSetting, () => DEFAULT_PIXELS.toString());
  set hpixelsSetting(String s) { writeValue(#hpixelsSetting, s); }
  @published
  String get vpixelsSetting => readValue(#vpixelsSetting, () => DEFAULT_PIXELS.toString());
  set vpixelsSetting(String s) { writeValue(#vpixelsSetting, s); }
  @published
  String get pixelSizeSetting => readValue(#pixelSizeSetting, () => DEFAULT_PIXEL_SIZE.toString());
  set pixelSizeSetting(String s) { writeValue(#pixelSizeSetting, s); }
  @published
  String get fgColor => readValue(#fgColor, () => 'White');
  set fgColor(String s) { writeValue(#fgColor, s); }
  @published
  String get bgColor => readValue(#bgColor, () => 'RGBA(0, 0, 0, 0.8)');
  set bgColor(String s) { writeValue(#bgColor, s); }
  @published
  bool get nogrids => readValue(#nogrids, () => false);
  set nogrids(bool b) => writeValue(#nogrids, b);
  @published
  String get colorSpace => readValue(#colorSpace, () => '8');
  set colorSpace(String s) => writeValue(#colorSpace, s);
  @published
  String get selectionContext => readValue(#selectionContext);
  set selectionContext(String s) => writeValue(#selectionContext, s);
  @published
  String get zippedJson => readValue(#zippedJson);
  set zippedJson(String s) => writeValue(#zippedJson, s);

  @reflectable
  int get hpixels => _parsePixels(hpixelsSetting);
  set hpixels(int i) { hpixelsSetting = i.toString(); }
  @reflectable
  int get vpixels => _parsePixels(vpixelsSetting);
  set vpixels(int i) { vpixelsSetting = i.toString(); }
  @reflectable
  int get pixelSize => _parsePixelSize(pixelSizeSetting);
  set pixelSize(int i) { pixelSizeSetting = i.toString(); }
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
  String get currentActionName =>
      canvas == null ? null : _getCurrentActionName(canvas.currentAction);

  @observable String gridColor = LIGHT_GRID_COLOR.toColorString();
  @observable String ansiTextUrl;
  @observable String shareLink;
  @observable ObservableMap commands = toObservable({
    'script': true
  });
  @observable String pythonArgs;
  @observable bool isStackingHistory = false;

  Timer zippedJsonUpdater;
  Function afterRendered;

  PixelCanvasElement get canvas => shadowRoot.querySelector('pixel-canvas');
  AnsiColorPaletteElement get _palette =>
      shadowRoot.querySelector('ansi-color-palette');
  FoldButtonElement get _settingFoldButton =>
      shadowRoot.querySelector('fold-button[target="#settings"]');
  Element get _controller => shadowRoot.querySelector('#controller');
  FoldButtonElement get _controllerFoldButton =>
      shadowRoot.querySelector('fold-button[target="#controller"]');
  Element get _container => shadowRoot.querySelector('#bgcolor-container');
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
    _asyncUpdateContainterSize();
    _startUrlFragmentObsevation();
    async((_) { _updateZipped();});
    _initLocalStorageProps();
  }

  void _initLocalStorageProps() {
    final saved = window.localStorage['commands'];
    if (saved != null) {
      print('load command: $saved');
      commands.keys
        .forEach((k) => commands[k] = (k == saved));
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

  void _loadZippedJsonFromHashFragment(String hash, [bool updateZippedJson = false]) {
    if (hash == null) return;

    final zipped = (hash.startsWith('#')) ? hash.substring(1) : hash;
    if (zipped.isEmpty) return;

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
  }

  void _loadPixels(List<List<int>> pixels, bool updateZippedJson) {
    if (pixels == null || pixels.isEmpty) return;

    vpixelsSetting = pixels.length.toString();
    hpixelsSetting = pixels.first.length.toString();

    afterRendered = () {
      new AnsiPixels.fromJson(pixels).forEach((x, y, code) {
        final String color = (code == null) ? null : getColorFromAnsiCode(code);
        canvas.setColor(x, y, color);
      });
      afterRendered = null;
      if (!updateZippedJson)
        // canncel zippedJson update because the browser history go forward
        new Timer(new Duration(milliseconds: 1000), () => _clearZippedJsonUpdater());
    };
  }

  void _initCallbacks() {
    canvas.drawingColor = getColorFromAnsiCode(0);
    _palette.selectByCodeInt(0);

    _palette.onColorChange.listen((e) {
      canvas.currentAction = null;
      canvas.drawingColor = e.newColor;
      notifyPropertyChange(#drawingColorCode, e.oldCode, e.newCode);
    });
    canvas.onActionChange.listen((e) {
      final oldHasSelection = _haveSelection(e.oldAction);
      final oldHasFloatLayer = _haveFloatLayer(e.oldAction);
      notifyPropertyChange(#hasSelection, oldHasSelection, hasSelection);
      notifyPropertyChange(#hasFloatLayer, oldHasFloatLayer, hasFloatLayer);
      notifyPropertyChange(#hasOutline, oldHasSelection || oldHasFloatLayer,
          hasOutline);

      final oldActionName = _getCurrentActionName(e.oldAction);
      notifyPropertyChange(#currentActionName, oldActionName, currentActionName);
    });
    notifyPropertyChange(#currentActionName, null, currentActionName);

    canvas.onPixelColorChange.listen((_) {
      _delayUpdateZipped();
    });
    canvas.onAfterRendering.listen((_) {
      if (afterRendered == null) return;
      afterRendered();
    });
  }

  hpixelsSettingChanged(String old) {
    notifyPropertyChange(#hpixels, _parsePixels(old), hpixels);
    _asyncUpdateContainterSize();
    _delayUpdateZipped();
  }
  vpixelsSettingChanged(String old) {
    notifyPropertyChange(#vpixels, _parsePixels(old), vpixels);
    _asyncUpdateContainterSize();
    _delayUpdateZipped();
  }

  pixelSizeSettingChanged(String old) {
    notifyPropertyChange(#pixelSize, _parsePixelSize(old), pixelSize);
    _asyncUpdateContainterSize();
    _delayUpdateZipped();
  }

  nogridsChanged() {
    // The `canvas.noGridlines` assignment directly is required.
    // Under normal circumstances, no gridlines config change will be
    // propergated by only using `<pixel-canvas ... noGridlines?="{{nogrids}}">`.
    // However, it is not working.
    canvas.noGridlines = nogrids;
    _delayUpdateZipped();
  }

  colorSpaceChanged() {
    _asyncUpdateContainterSize();
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
    final r = BASE_BG_COLOR.putColor(bg);
    final newColor = r.chooseColor([LIGHT_GRID_COLOR, DARK_GRID_COLOR]);
    if (newColor != null) gridColor = newColor.toColorString();
  }

  zippedJsonChanged(String old) {
    _updateAnsiTextUrl();
    _updateShareLink();
    _updatePythonArgs();
    _updateHistory();
  }

  void _updatePythonArgs() {
    pythonArgs = '-c "\$(curl -s $SCRIPT_URL)" "$zippedJson"';
  }

  _asyncUpdateContainterSize() =>
      async((_) => _updateContainterSize());

  _updateContainterSize() {
    final container = _container;
    final baseRect = container.getBoundingClientRect();
    final Rectangle boundingBox = container.children
      .map((child) => child.getBoundingClientRect())
      .where((Rectangle r) => r.width != 0 && r.height != 0)
      .fold(
          new Rectangle(baseRect.left, baseRect.top, 0, 0),
          (Rectangle prev, rect) => prev.boundingBox(rect));

    container.style
      ..height = '${boundingBox.height}px';
  }

  void _delayUpdateZipped([Duration delay]) {
    if (zippedJsonUpdater != null) return;

    if (delay == null) delay =  ZIPPED_JSON_UPDATE_DELAY;
    zippedJsonUpdater = new Timer(delay, () {
      _updateZipped();
    });
  }

  void _updateZipped() {
    zippedJson = toZippedJson();
    _clearZippedJsonUpdater();
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

  void _updateHistory() {
    final uri = Uri.parse(window.location.href);
    final newUri = new Uri(fragment: zippedJson, query: uri.query,
        host: uri.host, path: uri.path, port: uri.port, scheme: uri.scheme,
        userInfo: uri.userInfo);

    final hash = window.location.hash;
    if (isStackingHistory && hash != null && hash.isNotEmpty) {
      window.history.pushState(null, 'ANSI Pixels', newUri.toString());
    } else {
      window.history.replaceState(null, 'ANSI Pixels', newUri.toString());
    }
  }

  // elements events

  void deselectColor() {
    canvas.drawingColor = null;
    _palette.selectedCell = null;
  }

  void selectShareLink(FocusEvent e, _, Element target) {
    _updateZipped();

    if (target is! InputElement) return;
    async((_) {
      InputElement input = target;
      input.setSelectionRange(0, input.value.length);
    });
  }
  void updateShareLink() { async((_) => _updateShareLink()); }

  void downloadAsPng() => canvas.downloadAs('ansi-pixels.png');

  void foldAll(MouseEvent e) {
    _settingFoldButton.fold();
    _autoFoldController();
  }

  void stopPropergation(MouseEvent e) => e.stopPropagation();

  void cancelAction() => canvas.currentAction = null;

  void delete() {
    if (hasFloatLayer) {
      canvas.deleteFloatLayer();
    } else if (hasSelection) {
      canvas.deleteSelection();
    }
  }

  void selectCommand(Event e, _, Element target) {
    _updateZipped();

    if (target is! InputElement) return;
    async((_) {
      InputElement input = target;
      input.setSelectionRange(0, input.value.length);
    });
  }
  void updateAnsiTextUrl() { async((_) => _updateAnsiTextUrl()); }
  void updatePythonArgs() { async((_) => _updatePythonArgs()); }

  void _autoFoldController() {
    if (_isOverlapping(_controller, canvas)) {
      _controllerFoldButton.fold();
    }
  }

  bool _isOverlapping(Element e1, Element e2) {
    final r1 = e1.getBoundingClientRect();
    final r2 = e2.getBoundingClientRect();
    return r1.intersects(r2);
  }

  int _parsePixels(String s) => _parseInt(s, DEFAULT_PIXELS);
  int _parsePixelSize(String s) => _parseInt(s, DEFAULT_PIXEL_SIZE);

  Map toJson() => {
    'pixelSize': pixelSize,
    'bgColor': bgColor,
    'fgColor': fgColor,
    'colorSpace': colorSpace,
    'nogrids': nogrids,
    'pixels': _generateAnsiPixels()
  };

  AnsiPixels _generateAnsiPixels() =>
      new AnsiPixels.generate(hpixels, vpixels, (int x, int y) {
        final color = canvas.getColor(x, y);
        final code = getAnsiCodeFromColor(color);
        return code;
      });

  Object toZippedJson() => zip(JSON.encode(this), urlSafe: true);
}

int _parseInt(String s, int defaultValue) {
  if (s == null) return defaultValue;
  return int.parse(s, radix: 10, onError: (_) => defaultValue);
}

bool _haveSelection(Action a) =>
    a is SelectionAction && a.bounds.points.isNotEmpty;
bool _haveFloatLayer(Action a) =>
    a is FloatLayerAction && a.floatLayer.points.isNotEmpty;
bool _haveOutline(Action a) =>
    a is OutlinableAction && a.outline.isNotEmpty;
String _getCurrentActionName(Action a) {
  return a.runtimeType.toString().replaceFirst(new RegExp(r'Action$'), '');
}