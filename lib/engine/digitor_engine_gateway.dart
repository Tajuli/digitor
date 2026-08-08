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
    return '${_basename(path)}$size$implementation';
  }

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
    } catch (error) {
      _error = error.toString();
    }
    notifyListeners();
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

  void removeSelectedNode() {
    _mutate(() {
      final selected = _selectedNode;
      if (selected == null) return;
      graph.remove(selected);
      final replacement = graph.addSerialAfter(
        graph.endpoints.input,
        name: 'Grade',
      );
      _selectedNode = replacement;
      graph.select(replacement);
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
  }) {
    _mutate(() {
      _selectCurrent();
      graph.addPrimaryWheels(
        DigitorPrimaryWheels(
          lift: DigitorPrimaryWheel(master: lift),
          gamma: DigitorPrimaryWheel(master: gamma),
          gain: DigitorPrimaryWheel(master: gain),
          offset: DigitorPrimaryWheel(master: offset),
        ),
      );
    });
  }

  void applyLogWheels({
    required double shadows,
    required double midtones,
    required double highlights,
    required double global,
  }) {
    _mutate(() {
      _selectCurrent();
      graph.addLogWheels(
        DigitorLogWheels(
          shadows: DigitorLogWheel(master: shadows),
          midtones: DigitorLogWheel(master: midtones),
          highlights: DigitorLogWheel(master: highlights),
          global: DigitorLogWheel(master: global),
        ),
      );
    });
  }

  void applyRgbCurve(double midpointLift) {
    _mutate(() {
      _selectCurrent();
      final y = (0.5 + midpointLift).clamp(0.0, 1.0).toDouble();
      graph.addRgbCurves(
        DigitorRgbCurves(
          master: DigitorCurveChannel(
            points: <DigitorCurvePoint>[
              const DigitorCurvePoint(0, 0),
              DigitorCurvePoint(0.5, y),
              const DigitorCurvePoint(1, 1),
            ],
          ),
        ),
      );
    });
  }

  void applyQualifier({required double hueLow, required double hueHigh}) {
    _mutate(() {
      _selectCurrent();
      graph.addHslQualifier(
        DigitorHslQualifier(
          hue: DigitorQualifierRange(
            low: hueLow,
            high: hueHigh,
            softness: 0.05,
          ),
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

  void applyEffect({
    required DigitorNodeEffectType type,
    required double amount,
    required double radius,
  }) {
    _mutate(() {
      _selectCurrent();
      graph.addEffect(
        DigitorNodeEffect(type: type, amount: amount, radius: radius),
      );
    });
  }

  void applyPowerWindow({
    required DigitorPowerWindowShape shape,
    required double width,
    required double height,
    required double feather,
  }) {
    _mutate(() {
      _selectCurrent();
      graph.addPowerWindow(
        DigitorPowerWindow(
          shape: shape,
          width: width,
          height: height,
          feather: feather,
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
