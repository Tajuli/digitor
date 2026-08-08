import 'dart:async';

import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// UI-facing adapter only.
///
/// Digitor owns presentation state and file-picking UX. Renderer, decoder,
/// node graph, platform texture host and processing lifecycle are owned by the
/// public [DigitorEditorWorkspace] facade in DigitorEngine.
class DigitorEngineGateway extends ChangeNotifier {
  DigitorEditorWorkspace? _workspace;
  DigitorProductionMediaSnapshot? _media;

  bool _initializing = false;
  bool _ready = false;
  String? _error;
  String? _mediaPath;

  bool get initializing => _initializing;
  bool get ready => _ready;
  String? get error => _error;
  String? get mediaPath => _mediaPath;
  int? get selectedNode => _workspace?.selectedNode;
  DigitorRendererInfo? get renderer => _workspace?.renderer;
  DigitorFlutterHostCapabilities? get hostCapabilities =>
      _workspace?.hostCapabilities;
  DigitorProductionDecoderInfo? get decoder => _media?.decoder;
  DigitorProductionDecodedFrameInfo? get firstFrame => _media?.firstFrame;
  DigitorProductionNativeSurface? get nativeSurface => _media?.nativeSurface;

  DigitorEditorWorkspace get workspace {
    final value = _workspace;
    if (value == null) {
      throw StateError('DigitorEngine workspace is not ready.');
    }
    return value;
  }

  String get rendererLabel {
    final value = renderer;
    if (value == null) return 'Engine not initialized';
    return '${value.backendName} • ${value.deviceName}';
  }

  String get hostLabel {
    final value = hostCapabilities;
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
    final frame = firstFrame;
    final decoderInfo = decoder;
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
    final value = nativeSurface;
    if (value == null) return 'No native decoder surface';
    return '${value.platform.name} • ${value.handleType.name} • '
        '${value.pixelFormat.name} • ${value.width}×${value.height}';
  }

  String get recipeIdentity => _workspace?.recipeIdentity ?? '';

  Future<void> initialize() async {
    if (_ready || _initializing) return;
    _initializing = true;
    _error = null;
    notifyListeners();

    try {
      _workspace = await DigitorEditorWorkspace.create(
        preferredBackend: DigitorBackend.automatic,
        allowCpuFallback: true,
      );
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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;
      final snapshot = workspace.openMedia(path);
      _media = snapshot;
      _mediaPath = snapshot.path;
    } catch (error) {
      _error = error.toString();
    }
    notifyListeners();
  }

  void selectNode(int node) => _mutate(() => workspace.selectNode(node));
  void addSerialNode() => _mutate(workspace.addSerialNode);
  void addParallelNodes() => _mutate(workspace.addParallelNodes);
  void convertSelectedToParallel() =>
      _mutate(workspace.convertSelectedToParallel);
  void connectNodes(int source, int destination) =>
      _mutate(() => workspace.connectNodes(source, destination));
  void disconnectNodes(int source, int destination) =>
      _mutate(() => workspace.disconnectNodes(source, destination));
  void moveSelectedNode(double x, double y) =>
      _mutate(() => workspace.moveSelectedNode(x, y));
  void setSelectedEnabled(bool enabled) =>
      _mutate(() => workspace.setSelectedEnabled(enabled));
  void setSelectedBypassed(bool bypassed) =>
      _mutate(() => workspace.setSelectedBypassed(bypassed));
  void removeSelectedNode() => _mutate(workspace.removeSelectedNode);
  void clearSelectedOperations() => _mutate(workspace.clearSelectedOperations);

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
      workspace.addCorrection(
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
      workspace.addPrimaryWheels(
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
      workspace.addLogWheels(
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

  void applyRgbCurve(double midpointLift) =>
      applyRgbCurves(master: midpointLift);

  void applyRgbCurves({
    double master = 0,
    double red = 0,
    double green = 0,
    double blue = 0,
    int lutSize = 1024,
  }) {
    _mutate(() {
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

      workspace.addRgbCurves(
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
      workspace.addHslQualifier(
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
      workspace.addLut1d(
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
      workspace.addLut3d(
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
      workspace.addEffect(
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
      workspace.addPowerWindow(
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

  void _mutate(Object? Function() action) {
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
    final value = _workspace;
    _workspace = null;
    if (value != null) unawaited(value.close());
    super.dispose();
  }
}
