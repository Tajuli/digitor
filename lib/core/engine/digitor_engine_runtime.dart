import 'dart:convert';

import 'package:digitor/features/editor/domain/models/color/color_node_graph.dart';
import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:flutter/foundation.dart';

/// Process-wide internal bridge between the Flutter editor and DigitorEngine.
///
/// The Flutter widgets remain UI/presentation. Renderer selection, transport
/// state and production node recipes are mirrored into the native engine so a
/// native presenter/exporter can consume the same state without translating
/// the grade a second time.
final class DigitorEngineRuntime extends ChangeNotifier {
  DigitorEngineRuntime._();

  static final DigitorEngineRuntime instance = DigitorEngineRuntime._();

  DigitorNativeEngine? _engine;
  DigitorTimelineSession? _timeline;
  DigitorNativeNodeGraph? _activeGraph;
  final Map<String, int> _nativeNodeIds = <String, int>{};
  int _timelineRevision = 0;
  String? _topologySignature;
  String? _nativeRecipeIdentity;
  String? _error;
  DigitorRendererInformation? _renderer;

  bool get isReady => _engine?.isInitialized == true;
  DigitorRendererInformation? get renderer => _renderer;
  String? get error => _error;
  String? get nativeRecipeIdentity => _nativeRecipeIdentity;
  DigitorTimelineSession? get timelineSession => _timeline;

  void initialize() {
    if (isReady) return;
    try {
      final engine = DigitorNativeEngine.open();
      _renderer = engine.initialize(
        configuration: const DigitorEngineConfiguration(
          preferredBackend: DigitorRendererBackend.auto,
          enableValidation: false,
          allowCpuFallback: true,
        ),
      );
      _engine = engine;
      _error = null;
    } catch (error) {
      _error = 'DigitorEngine initialization failed: $error';
    }
    notifyListeners();
  }

  /// Publishes the immutable timeline revision used by native transport.
  void publishTimeline({
    required Duration duration,
    required int videoTrackCount,
    required int audioTrackCount,
  }) {
    if (!isReady) initialize();
    if (!isReady) return;
    try {
      _timeline ??= DigitorTimelineSession.create(
        sampleRate: 48000,
        channels: 2,
        durationUs: duration.inMicroseconds,
      );
      _timelineRevision++;
      _timeline!.publish(
        revision: _timelineRevision,
        durationUs: duration.inMicroseconds,
        videoTrackCount: videoTrackCount,
        audioTrackCount: audioTrackCount,
      );
      _error = null;
    } catch (error) {
      _error = 'DigitorEngine timeline publish failed: $error';
    }
  }

  void play() => _transport('play', (session) => session.play());
  void pause() => _transport('pause', (session) => session.pause());
  void stop() => _transport('stop', (session) => session.stop());
  void seek(Duration position) =>
      _transport('seek', (session) => session.seek(position.inMicroseconds));

  void _transport(
    String operation,
    void Function(DigitorTimelineSession session) action,
  ) {
    final session = _timeline;
    if (session == null) return;
    try {
      action(session);
      _error = null;
    } catch (error) {
      _error = 'DigitorEngine $operation failed: $error';
    }
  }

  /// Mirrors the active Digitor color graph into the production native graph.
  /// Topology is rebuilt only when links/nodes change; slider drags only replace
  /// operations on the already-created native nodes.
  void syncColorGraph(ColorNodeGraph graph) {
    if (!isReady) initialize();
    if (!isReady) return;
    try {
      final signature = _signature(graph);
      if (_activeGraph == null || signature != _topologySignature) {
        _rebuildGraph(graph);
        _topologySignature = signature;
      }
      _syncNodeStateAndOperations(graph);
      _nativeRecipeIdentity = _activeGraph?.recipeIdentity();
      _error = null;
    } catch (error) {
      _error = 'DigitorEngine color graph sync failed: $error';
    }
  }

  String _signature(ColorNodeGraph graph) {
    final nodes = graph.nodes
        .map((node) => '${node.id}:${node.type.name}')
        .toList()
      ..sort();
    final links = graph.connections
        .map((connection) => '${connection.from}>${connection.to}')
        .toList()
      ..sort();
    return '${nodes.join('|')}#${links.join('|')}';
  }

  void _rebuildGraph(ColorNodeGraph graph) {
    _activeGraph?.dispose();
    _activeGraph = DigitorNativeNodeGraph.create();
    _nativeNodeIds.clear();

    final native = _activeGraph!;
    final endpoints = native.endpoints();
    final input = graph.nodes.firstWhere((node) => node.type == ColorNodeType.input);
    final output = graph.nodes.firstWhere((node) => node.type == ColorNodeType.output);
    _nativeNodeIds[input.id] = endpoints.input;
    _nativeNodeIds[output.id] = endpoints.output;

    _buildDownstream(graph, input.id, endpoints.input, <String>{});
  }

  void _buildDownstream(
    ColorNodeGraph graph,
    String appAnchorId,
    int nativeAnchorId,
    Set<String> visited,
  ) {
    if (!visited.add(appAnchorId)) return;
    final outgoing = graph.connections
        .where((connection) => connection.from == appAnchorId)
        .map((connection) => graph.nodeById(connection.to))
        .whereType<ColorNode>()
        .toList();

    if (outgoing.isEmpty || outgoing.any((node) => node.type == ColorNodeType.output)) {
      return;
    }

    final serial = outgoing.where((node) => node.type == ColorNodeType.serial).toList();
    final parallel = outgoing.where((node) => node.type == ColorNodeType.parallel).toList();

    if (serial.length == 1 && parallel.isEmpty && outgoing.length == 1) {
      final appNode = serial.single;
      final nativeNode = _activeGraph!.addSerialAfter(nativeAnchorId, name: appNode.name);
      _nativeNodeIds[appNode.id] = nativeNode;
      _buildDownstream(graph, appNode.id, nativeNode, visited);
      return;
    }

    if (parallel.length == 2 && serial.isEmpty && outgoing.length == 2) {
      final first = parallel[0];
      final second = parallel[1];
      final appMixerIdsA = graph.connections
          .where((connection) => connection.from == first.id)
          .map((connection) => connection.to)
          .toSet();
      final appMixerIdsB = graph.connections
          .where((connection) => connection.from == second.id)
          .map((connection) => connection.to)
          .toSet();
      final shared = appMixerIdsA.intersection(appMixerIdsB);
      final appMixer = shared
          .map(graph.nodeById)
          .whereType<ColorNode>()
          .where((node) => node.type == ColorNodeType.parallelMixer)
          .firstOrNull;
      if (appMixer == null) {
        throw StateError('Parallel branches do not share a mixer.');
      }

      final nativeBranches = _activeGraph!.addParallelAfter(
        nativeAnchorId,
        firstName: first.name,
        secondName: second.name,
      );
      _nativeNodeIds[first.id] = nativeBranches.first;
      _nativeNodeIds[second.id] = nativeBranches.second;

      final decoded = jsonDecode(_activeGraph!.toJson()) as Map<String, dynamic>;
      final nodes = (decoded['nodes'] as List).whereType<Map>().toList();
      final nativeMixer = nodes.firstWhere((entry) {
        if ((entry['kind'] as num?)?.toInt() != 3) return false;
        final inputs = ((entry['inputs'] as List?) ?? const [])
            .whereType<num>()
            .map((value) => value.toInt())
            .toSet();
        return inputs.contains(nativeBranches.first) &&
            inputs.contains(nativeBranches.second);
      });
      final nativeMixerId = (nativeMixer['id'] as num).toInt();
      _nativeNodeIds[appMixer.id] = nativeMixerId;
      _buildDownstream(graph, appMixer.id, nativeMixerId, visited);
      return;
    }

    throw StateError(
      'This color topology is not representable by the current public DigitorEngine node ABI.',
    );
  }

  void _syncNodeStateAndOperations(ColorNodeGraph graph) {
    final native = _activeGraph!;
    for (final node in graph.nodes.where((node) => node.supportsProcessing)) {
      final nativeId = _nativeNodeIds[node.id];
      if (nativeId == null) continue;
      native
        ..setPosition(nativeId, DigitorNodePosition(node.position.dx, node.position.dy))
        ..setEnabled(nativeId, node.enabled)
        ..select(nativeId)
        ..clearOperations(nativeId);

      if (node.wheels.previewEnabled) {
        native.addPrimaryWheels(_primaryWheels(node.wheels));
      }
      if (node.curves.previewEnabled) {
        native.addRgbCurves(_curves(node.curves));
      }
      if (node.qualifier.enabled) {
        native.addHslQualifier(_qualifier(node.qualifier));
      }
    }

    final selected = graph.selectedProcessingNode;
    if (selected != null) {
      final nativeId = _nativeNodeIds[selected.id];
      if (nativeId != null) native.select(nativeId);
    }
  }

  DigitorPrimaryWheels _primaryWheels(ColorWheelSettings wheels) {
    DigitorRgbValue chroma(ColorWheelControl control, {required bool multiplicative}) {
      final x = control.chroma.dx.clamp(-1.0, 1.0).toDouble();
      final y = control.chroma.dy.clamp(-1.0, 1.0).toDouble();
      final r = x * .25 - y * .08;
      final g = -x * .13 - y * .13;
      final b = -x * .12 + y * .21;
      final base = multiplicative ? 1.0 : 0.0;
      return DigitorRgbValue(base + r, base + g, base + b);
    }

    return DigitorPrimaryWheels(
      lift: DigitorPrimaryWheelValue(
        rgb: chroma(wheels.lift, multiplicative: false),
        master: wheels.lift.luminance,
      ),
      gamma: DigitorPrimaryWheelValue(
        rgb: chroma(wheels.gamma, multiplicative: true),
        master: 1 + wheels.gamma.luminance * .5,
      ),
      gain: DigitorPrimaryWheelValue(
        rgb: chroma(wheels.gain, multiplicative: true),
        master: 1 + wheels.gain.luminance * .75,
      ),
      offset: DigitorPrimaryWheelValue(
        rgb: chroma(wheels.offset, multiplicative: false),
        master: wheels.offset.luminance,
      ),
    );
  }

  DigitorRgbCurves _curves(ColorCurveSettings curves) {
    DigitorCurveChannel channel(List<Offset> values) => DigitorCurveChannel(
          points: values
              .map((point) => DigitorCurvePoint(point.dx, point.dy))
              .toList(growable: false),
        );
    return DigitorRgbCurves(
      master: channel(curves.y),
      red: channel(curves.r),
      green: channel(curves.g),
      blue: channel(curves.b),
      lutSize: 1024,
    );
  }

  DigitorHslQualifier _qualifier(HslQualifierSettings qualifier) {
    final halfWidth = qualifier.hueWidth.clamp(0.0, 1.0).toDouble() * .5;
    final low = (qualifier.hueCenter - halfWidth).clamp(0.0, 1.0).toDouble();
    final high = (qualifier.hueCenter + halfWidth).clamp(0.0, 1.0).toDouble();
    return DigitorHslQualifier(
      hue: DigitorQualifierRange(low: low, high: high, softness: qualifier.softness),
      saturation: DigitorQualifierRange(
        low: qualifier.saturationLow,
        high: qualifier.saturationHigh,
        softness: qualifier.softness,
      ),
      luminance: DigitorQualifierRange(
        low: qualifier.luminanceLow,
        high: qualifier.luminanceHigh,
        softness: qualifier.softness,
      ),
      blur: qualifier.blur,
      denoise: qualifier.denoise,
      invert: qualifier.inverted,
    );
  }

  /// Direct access to Engine-only operations that do not yet have dedicated
  /// Flutter controls. They are applied to the currently selected native node.
  void addLogWheels(DigitorLogWheels value) => _activeGraph?.addLogWheels(value);
  void addLut1d(List<DigitorLutColor> values) => _activeGraph?.addLut1d(values);
  void addLut3d(int size, List<DigitorLutColor> values) =>
      _activeGraph?.addLut3d(size, values);
  void addEffect(DigitorNodeEffect value) => _activeGraph?.addEffect(value);
  void addPowerWindow(DigitorPowerWindow value) => _activeGraph?.addPowerWindow(value);

  @override
  void dispose() {
    _activeGraph?.dispose();
    _activeGraph = null;
    _timeline?.dispose();
    _timeline = null;
    _engine?.shutdown();
    _engine = null;
    super.dispose();
  }
}
