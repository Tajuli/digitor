import 'dart:async';

import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// UI-facing adapter only. All media, graph and image-processing work is
/// delegated to DigitorEngine.
class DigitorEngineGateway extends ChangeNotifier {
  DigitorEngine? _engine;
  DigitorNodeGraph? _graph;
  DigitorProductionMediaSource? _media;
  DigitorFlutterPlatformHost? _platformHost;
  DigitorRendererInfo? _renderer;
  DigitorFlutterHostCapabilities? _hostCapabilities;
  DigitorProductionDecoderInfo? _decoder;
  DigitorProductionDecodedFrameInfo? _firstFrame;
  DigitorProductionNativeSurface? _nativeSurface;

  bool _initializing = false;
  bool _ready = false;
  String? _error;
  String? _mediaPath;
  int? _selectedNode;

  bool get initializing => _initializing;
  bool get ready => _ready;
  String? get error => _error;
  String? get mediaPath => _mediaPath;
  int? get selectedNode => _selectedNode;
  DigitorRendererInfo? get renderer => _renderer;
  DigitorFlutterHostCapabilities? get hostCapabilities => _hostCapabilities;
  DigitorProductionDecoderInfo? get decoder => _decoder;
  DigitorProductionDecodedFrameInfo? get firstFrame => _firstFrame;
  DigitorProductionNativeSurface? get nativeSurface => _nativeSurface;

  DigitorNodeGraph get graph {
    final value = _graph;
    if (value == null) {
      throw StateError('DigitorEngine graph is not ready.');
    }
    return value;
  }

  String get rendererLabel {
    final value = _renderer;
    if (value == null) return 'Engine not initialized';
    return '${value.backendName} • ${value.deviceName}';
  }

  String get hostLabel {
    final value = _hostCapabilities;
    if (value == null) return 'Texture host unavailable';
    final mode = value.directDescriptorPresentation
        ? 'direct texture'
        : value.renderTargetPresentation
            ? 'render target'
            : 'no GPU presentation';
    return '${value.platform} • $mode';
  }

  String get mediaLabel {
    final path = _mediaPath;
    if (path == null) return 'No media loaded';
    final frame = _firstFrame;
    final decoderInfo = _decoder;
    final size = frame == null ? '' : ' • ${frame.width}×${frame.height}';
    final implementation =
        decoderInfo == null ? '' : ' • ${decoderInfo.implementation}';
    final residency = frame == null
        ? ''
        : frame.gpuResident
            ? ' • GPU resident'
            : frame.cpuResident
                ? ' • CPU resident'
                : '';
    return '${_basename(path)}$size$implementation$residency';
  }

  String get nativeSurfaceLabel {
    final value = _nativeSurface;
    if (value == null) return 'No native decoder surface';
    return '${value.platform.name} • ${value.handleType.name} • '
        '${value.pixelFormat.name} • ${value.width}×${value.height}';
  }

  String get recipeIdentity => _graph?.recipeIdentity ?? '';

  Future<void> initialize() async {
    if (_ready || _initializing) return;
    _initializing = true;
    _error = null;
    notifyListeners();

    try {
      _engine = DigitorEngine.initialize(
        preferredBackend: DigitorBackend.automatic,
        allowCpuFallback: true,
      );
      _renderer = _engine!.rendererInfo;
      _graph = DigitorNodeGraph.create();
      final endpoints = graph.endpoints;
      _selectedNode = graph.addSerialAfter(endpoints.input, name: 'Grade 01');
      graph.select(_selectedNode!);

      _platformHost = DigitorFlutterPlatformHost();
      try {
        _hostCapabilities = await _platformHost!.capabilities();
      } catch (_) {
        _hostCapabilities = null;
      }
      _ready = true;
    } catch (error) {
      _error = error.toString();
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> pickMedia() async {
    if (!_ready) return;
    _error = null;
    notifyListeners();

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;

      _media?.close();
      _media = DigitorProductionMediaSource.open(
        path,
        hardwareDecode: DigitorHardwareDecode.automatic,
        allowCpuFallback: true,
        requireZeroCopy: false,
      );
      _mediaPath = path;
      _decoder = _media!.decoderInfo;
      _firstFrame = _media!.decode(0);
      _nativeSurface = null;
      if (_firstFrame!.gpuResident && _decoder!.nativeSurfaceOutput) {
        try {
          _nativeSurface = _media!.nativeSurface;
        } catch (_) {
          _nativeSurface = null;
        }
      }
    } catch (error) {
      _error = error.toString();
    }
    notifyListeners();
  }

  void selectNode(int node) {
    _mutate(() {
      graph.select(node);
      _selectedNode = node;
    });
  }

  void addSerialNode() {
    _mutate(() {
      final after = _selectedNode ?? graph.endpoints.input;
      final node = graph.addSerialAfter(after, name: 'Serial Node');
      _selectedNode = node;
      graph.select(node);
    });
  }

  void addParallelNodes() {
    _mutate(() {
      final after = _selectedNode ?? graph.endpoints.input;
      final nodes = graph.addParallelAfter(after);
      _selectedNode = nodes.first;
      graph.select(nodes.first);
    });
  }

  void convertSelectedToParallel() {
    _mutate(() {
      _selectCurrent();
      graph.convertToParallel(_selectedNode!);
    });
  }

  void connectNodes(int source, int destination) {
    _mutate(() => graph.connect(source, destination));
  }

  void disconnectNodes(int source, int destination) {
    _mutate(() => graph.disconnect(source, destination));
  }

  void moveSelectedNode(double x, double y) {
    _mutate(() {
      _selectCurrent();
      graph.setPosition(_selectedNode!, x, y);
    });
  }

  void setSelectedEnabled(bool enabled) {
    _mutate(() {
      _selectCurrent();
      graph.setEnabled(_selectedNode!, enabled);
    });
  }

  void setSelectedBypassed(bool bypassed) {
    _mutate(() {
      _selectCurrent();
      graph.setBypassed(_selectedNode!, bypassed);
    });
  }

  void removeSelectedNode() {
    _mutate(() {
      final selected = _selectedNode;
      if (selected == null) return;
      graph.remove(selected);
      final endpoints = graph.endpoints;
      final nativeSelection = graph.selectedNode;
      if (nativeSelection == endpoints.input || nativeSelection == endpoints.output) {
        _selectedNode = null;
      } else {
        _selectedNode = nativeSelection;
      }
    });
  }

  void clearSelectedOperations() {
    _mutate(() {
      _selectCurrent();
      graph.clearOperations(_selectedNode!);
    });
  }

  void applyCorrection({
    required double exposure,
    required double contrast,
    required double saturation,
    required double temperature,
    required double tint,
    required double highlights,
    required double shadows,
    required double hue,
    required double colorBoost,
  }) {
    _mutate(() {
      _selectCurrent();
      graph.addCorrection(
        DigitorCorrection(
          exposure: exposure,
          contrast: contrast,
          saturation: saturation,
          temperature: temperature,
          tint: tint,
          highlights: highlights,
          shadows: shadows,
          hue: hue,
          colorBoost: colorBoost,
        ),
      );
    });
  }

  void applyPrimaryWheels({
    required double lift,
    required double gamma,
    required double gain,
    required double offset,
    DigitorRgb liftRgb = const DigitorRgb.neutral(),
    DigitorRgb gammaRgb = const DigitorRgb.neutral(),
    DigitorRgb gainRgb = const DigitorRgb.neutral(),
    DigitorRgb offsetRgb = const DigitorRgb.neutral(),
  }) {
    _mutate(() {
      _selectCurrent();
      graph.addPrimaryWheels(
        DigitorPrimaryWheels(
          lift: DigitorPrimaryWheel(master: lift, rgb: liftRgb),
          gamma: DigitorPrimaryWheel(master: gamma, rgb: gammaRgb),
          gain: DigitorPrimaryWheel(master: gain, rgb: gainRgb),
          offset: DigitorPrimaryWheel(master: offset, rgb: offsetRgb),
        ),
      );
    });
  }

  void applyLogWheels({
    required double shadows,
    required double midtones,
    required double highlights,
    required double global,
    DigitorRgb shadowsRgb = const DigitorRgb.neutral(),
    DigitorRgb midtonesRgb = const DigitorRgb.neutral(),
    DigitorRgb highlightsRgb = const DigitorRgb.neutral(),
    DigitorRgb globalRgb = const DigitorRgb.neutral(),
    double shadowPivot = 0.33,
    double highlightPivot = 0.67,
    double transitionWidth = 0.1,
  }) {
    _mutate(() {
      _selectCurrent();
      graph.addLogWheels(
        DigitorLogWheels(
          shadows: DigitorLogWheel(master: shadows, rgb: shadowsRgb),
          midtones: DigitorLogWheel(master: midtones, rgb: midtonesRgb),
          highlights: DigitorLogWheel(master: highlights, rgb: highlightsRgb),
          global: DigitorLogWheel(master: global, rgb: globalRgb),
          shadowPivot: shadowPivot,
          highlightPivot: highlightPivot,
          transitionWidth: transitionWidth,
        ),
      );
    });
  }

  void applyRgbCurve(double midpointLift) {
    applyRgbCurves(master: midpointLift);
  }

  void applyRgbCurves({
    double master = 0,
    double red = 0,
    double green = 0,
    double blue = 0,
    int lutSize = 1024,
  }) {
    _mutate(() {
      _selectCurrent();
      DigitorCurveChannel channel(double lift) {
        final y = (0.5 + lift).clamp(0.0, 1.0).toDouble();
        return DigitorCurveChannel(
          points: <DigitorCurvePoint>[
            const DigitorCurvePoint(0, 0),
            DigitorCurvePoint(0.5, y),
            const DigitorCurvePoint(1, 1),
          ],
        );
      }

      graph.addRgbCurves(
        DigitorRgbCurves(
          master: channel(master),
          red: channel(red),
          green: channel(green),
          blue: channel(blue),
          lutSize: lutSize,
        ),
      );
    });
  }

  void applyQualifier({
    required double hueLow,
    required double hueHigh,
    double hueSoftness = 0.05,
    double saturationLow = 0,
    double saturationHigh = 1,
    double saturationSoftness = 0,
    double luminanceLow = 0,
    double luminanceHigh = 1,
    double luminanceSoftness = 0,
    double blur = 0,
    double denoise = 0,
    double cleanBlack = 0,
    double cleanWhite = 0,
    bool invert = false,
    bool matteOutput = false,
  }) {
    _mutate(() {
      _selectCurrent();
      graph.addHslQualifier(
        DigitorHslQualifier(
          hue: DigitorQualifierRange(
            low: hueLow,
            high: hueHigh,
            softness: hueSoftness,
          ),
          saturation: DigitorQualifierRange(
            low: saturationLow,
            high: saturationHigh,
            softness: saturationSoftness,
          ),
          luminance: DigitorQualifierRange(
            low: luminanceLow,
            high: luminanceHigh,
            softness: luminanceSoftness,
          ),
          blur: blur,
          denoise: denoise,
          cleanBlack: cleanBlack,
          cleanWhite: cleanWhite,
          invert: invert,
          matteOutput: matteOutput,
        ),
      );
    });
  }

  void applyIdentityLut() {
    _mutate(() {
      _selectCurrent();
      graph.addLut1d(
        const <DigitorLutColor>[
          DigitorLutColor(0, 0, 0),
          DigitorLutColor(1, 1, 1),
        ],
      );
    });
  }

  void applyIdentityLut3d({
    DigitorLutInterpolation interpolation = DigitorLutInterpolation.tetrahedral,
  }) {
    _mutate(() {
      _selectCurrent();
      graph.addLut3d(
        2,
        const <DigitorLutColor>[
          DigitorLutColor(0, 0, 0),
          DigitorLutColor(1, 0, 0),
          DigitorLutColor(0, 1, 0),
          DigitorLutColor(1, 1, 0),
          DigitorLutColor(0, 0, 1),
          DigitorLutColor(1, 0, 1),
          DigitorLutColor(0, 1, 1),
          DigitorLutColor(1, 1, 1),
        ],
        interpolation: interpolation,
      );
    });
  }

  void applyEffect({
    required DigitorNodeEffectType type,
    required double amount,
    required double radius,
    double angle = 0,
    int seed = 0,
  }) {
    _mutate(() {
      _selectCurrent();
      graph.addEffect(
        DigitorNodeEffect(
          type: type,
          amount: amount,
          radius: radius,
          angle: angle,
          seed: seed,
        ),
      );
    });
  }

  void applyPowerWindow({
    required DigitorPowerWindowShape shape,
    required double width,
    required double height,
    required double feather,
    double centerX = 0.5,
    double centerY = 0.5,
    double rotation = 0,
    double opacity = 1,
    bool invert = false,
  }) {
    _mutate(() {
      _selectCurrent();
      graph.addPowerWindow(
        DigitorPowerWindow(
          shape: shape,
          centerX: centerX,
          centerY: centerY,
          width: width,
          height: height,
          rotation: rotation,
          feather: feather,
          opacity: opacity,
          invert: invert,
        ),
      );
    });
  }

  void _selectCurrent() {
    final selected = _selectedNode;
    if (selected == null) throw StateError('Select a node first.');
    graph.select(selected);
  }

  void _mutate(void Function() action) {
    _error = null;
    try {
      action();
    } catch (error) {
      _error = error.toString();
    }
    notifyListeners();
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  @override
  void dispose() {
    _media?.close();
    _graph?.dispose();
    final host = _platformHost;
    if (host != null) unawaited(host.close());
    final engine = _engine;
    if (engine != null) unawaited(engine.close());
    super.dispose();
  }
}
