import 'dart:async';

import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:file_selector/file_selector.dart';

import 'engine_feature_catalog.dart';
import 'engine_gateway.dart';

/// Direct DigitorEngine integration. Flutter owns only UI state and user intent;
/// decode, rendering, grading, node execution, playback and export remain in
/// DigitorEngine.
final class DigitorFfiEngineGateway implements EngineGateway {
  final _snapshotController = StreamController<EngineSnapshot>.broadcast();
  final _progressController = StreamController<EngineProgress>.broadcast();
  final _eventController = StreamController<EngineEvent>.broadcast();

  DigitorEditorWorkspace? _workspace;
  Timer? _statusTimer;
  bool _disposed = false;
  bool _projectOpen = false;
  String? _mediaPath;

  final Map<String, double> _values = <String, double>{};
  final Map<String, bool> _flags = <String, bool>{};

  @override
  Stream<EngineSnapshot> get snapshots => _snapshotController.stream;
  @override
  Stream<EngineProgress> get progress => _progressController.stream;
  @override
  Stream<EngineEvent> get events => _eventController.stream;

  DigitorEditorWorkspace get _w {
    final value = _workspace;
    if (value == null) throw StateError('DigitorEngine is not initialized.');
    return value;
  }

  @override
  Future<void> initialize() async {
    if (_workspace != null) return;
    final workspace = await DigitorEditorWorkspace.create();
    _workspace = workspace;
    _statusTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _emitSnapshot(),
    );
    _emitSnapshot();
    _event('engineReady', <String, Object?>{
      'engineVersion': DigitorEngine.version,
      'backend': workspace.renderer.backendName,
      'device': workspace.renderer.deviceName,
      'gpu': workspace.renderer.isGpu,
      'productionHostRegistered': workspace.productionHostRegistered,
      'platformHost': workspace.hostCapabilities?.platform,
    });
  }

  @override
  Future<List<EngineCapability>> discoverCapabilities() async {
    final workspace = _w;
    final host = workspace.hostCapabilities;
    final metadata = <String, Object?>{
      'backend': workspace.renderer.backendName,
      'device': workspace.renderer.deviceName,
      'isGpu': workspace.renderer.isGpu,
      'compute': workspace.renderer.supportsCompute,
      'fp16': workspace.renderer.supportsFp16,
      'fp32': workspace.renderer.supportsFp32,
      'productionHostRegistered': workspace.productionHostRegistered,
      'platformHost': host?.platform,
      'directDescriptorPresentation': host?.directDescriptorPresentation ?? false,
      'renderTargetPresentation': host?.renderTargetPresentation ?? false,
    };
    return engineFeatureCatalog
        .map(
          (feature) => EngineCapability(
            id: feature.id,
            category: feature.workspace.label,
            title: feature.title,
            supported: _supportedFeature(feature.id, workspace),
            metadata: metadata,
          ),
        )
        .toList(growable: false);
  }

  bool _supportedFeature(String id, DigitorEditorWorkspace workspace) {
    const direct = <String>{
      'media.import',
      'media.decode',
      'media.metadata',
      'media.zeroCopy',
      'color.correction',
      'effects.masksWindows',
      'effects.blur',
      'effects.sharpen',
      'effects.glow',
      'effects.grain',
      'effects.vignette',
      'effects.motionBlur',
      'nodes.graph',
      'nodes.connections',
      'audio.sync',
      'audio.track',
      'playback.transport',
      'runtime.backend',
      'export.production',
    };
    if (id == 'export.production') return workspace.productionHostRegistered;
    return direct.contains(id);
  }

  @override
  Future<void> dispatch(EngineIntent intent) async {
    if (_disposed) return;
    final action = intent.action;
    final value = intent.arguments['value'];

    if (action == 'media.import.requestPicker' ||
        action == 'project.lifecycle.open') {
      await _importMedia();
      return;
    }
    if (action == 'project.lifecycle.new') {
      _projectOpen = true;
      _mediaPath = null;
      _values.clear();
      _flags.clear();
      _emitSnapshot(message: 'New project');
      return;
    }
    if (action == 'project.lifecycle.save') {
      _event('projectSaveRequested', <String, Object?>{
        'recipeIdentity': _w.recipeIdentity,
        'graphRevision': _w.graphRevision,
        'parameterRevision': _w.parameterRevision,
      });
      return;
    }

    if (action.startsWith('color.correction.')) {
      final key = action.substring('color.correction.'.length);
      if (value is num) {
        _values['correction.$key'] = value.toDouble();
        _rebuildSelectedOperations();
      }
      return;
    }

    if (action.startsWith('effects.masksWindows.')) {
      _handleWindow(action, value);
      return;
    }
    if (action.startsWith('effects.')) {
      _handleEffect(action, value);
      return;
    }

    if (action.startsWith('nodes.graph.')) {
      switch (action) {
        case 'nodes.graph.addSerial':
          _w.addSerialNode();
          break;
        case 'nodes.graph.addParallel':
          _w.addParallelNodes();
          break;
        default:
          _eventUnsupported(action);
          return;
      }
      _emitSnapshot();
      return;
    }

    if (action == 'nodes.connections.bypass' && value is bool) {
      _w.setSelectedBypassed(value);
      _emitSnapshot();
      return;
    }

    if (action.startsWith('playback.transport.')) {
      _handleTransport(action, value);
      return;
    }

    if (action == 'audio.track.gain' && value is num) {
      _values['audio.gain'] = value.toDouble();
      _applyAudioControls();
      return;
    }
    if (action == 'timeline.speed.rate' && value is num) {
      _values['playback.rate'] = value.toDouble();
      _applyAudioControls();
      return;
    }
    if (action == 'audio.sync.latencyMs' && value is num) {
      final sync = DigitorAudioSync().probe(
        manualOffsetUs: (value.toDouble() * 1000).round(),
        manualOverride: true,
      );
      _event('audioSync', <String, Object?>{
        'measuredAvailable': sync.measuredAvailable,
        'measuredLatencyUs': sync.measuredLatencyUs,
        'effectiveOffsetUs': sync.effectiveOffsetUs,
      });
      return;
    }

    if (action == 'export.production.start') {
      await _exportCurrentMedia();
      return;
    }

    if (action == 'runtime.backend.inspect' ||
        action == 'media.metadata.inspect') {
      _emitDiagnostics();
      return;
    }

    _eventUnsupported(action);
  }

  Future<void> _importMedia() async {
    final file = await openFile();
    if (file == null) return;
    final media = _w.openMedia(file.path);
    _mediaPath = file.path;
    _projectOpen = true;
    _emitSnapshot(message: 'Media opened');
    _event('mediaOpened', <String, Object?>{
      'path': media.path,
      'decoder': media.decoder.implementation,
      'hardwareAccelerated': media.decoder.hardwareAccelerated,
      'nativeSurfaceOutput': media.decoder.nativeSurfaceOutput,
      'strictGpuPath': media.strictGpuPath,
      'width': media.firstFrame.width,
      'height': media.firstFrame.height,
      'pixelFormat': media.firstFrame.pixelFormat.name,
      'gpuResident': media.firstFrame.gpuResident,
      'cpuResident': media.firstFrame.cpuResident,
    });
  }

  void _handleTransport(String action, Object? value) {
    final status = _w.timelineStatus();
    switch (action) {
      case 'playback.transport.playPause':
        if (status.playbackState == DigitorPlaybackState.playing) {
          _w.pause();
        } else {
          _w.play();
        }
        break;
      case 'playback.transport.previousFrame':
        _w.seek((status.positionUs - 33333).clamp(0, 1 << 62).toInt());
        break;
      case 'playback.transport.nextFrame':
        _w.seek((status.positionUs + 33333).clamp(0, 1 << 62).toInt());
        break;
      case 'playback.transport.stop':
        _w.stop();
        break;
      case 'playback.transport.seek':
        if (value is num) _w.seek(value.toInt());
        break;
      default:
        _eventUnsupported(action);
        return;
    }
    _emitSnapshot();
  }

  void _applyAudioControls() {
    final current = _w.timelineStatus();
    _w.setAudioControls(
      masterGainDb: _values['audio.gain'] ?? current.masterGainDb,
      playbackRate: _values['playback.rate'] ?? current.playbackRate,
      preservePitch: current.preservePitch,
      enableDynamics: current.enableDynamics,
    );
    _emitSnapshot();
  }

  void _handleEffect(String action, Object? value) {
    const types = <String, DigitorNodeEffectType>{
      'effects.blur.amount': DigitorNodeEffectType.blur,
      'effects.sharpen.amount': DigitorNodeEffectType.sharpen,
      'effects.glow.amount': DigitorNodeEffectType.glow,
      'effects.grain.amount': DigitorNodeEffectType.filmGrain,
      'effects.vignette.amount': DigitorNodeEffectType.vignette,
      'effects.motionBlur.amount': DigitorNodeEffectType.motionBlur,
    };
    final type = types[action];
    if (type == null || value is! num) {
      _eventUnsupported(action);
      return;
    }
    _values['effect.${type.name}'] = value.toDouble();
    _rebuildSelectedOperations();
  }

  void _handleWindow(String action, Object? value) {
    if (action.endsWith('.feather') && value is num) {
      _values['window.feather'] = value.toDouble();
    } else if (action.endsWith('.invert') && value is bool) {
      _flags['window.invert'] = value;
    } else {
      _eventUnsupported(action);
      return;
    }
    _rebuildSelectedOperations();
  }

  void _rebuildSelectedOperations() {
    _w.clearSelectedOperations();
    if (_values.keys.any((key) => key.startsWith('correction.'))) {
      _w.addCorrection(
        DigitorCorrection(
          exposure: _values['correction.exposure'] ?? 0,
          contrast: _values['correction.contrast'] ?? 0,
          saturation: _values['correction.saturation'] ?? 0,
          temperature: _values['correction.temperature'] ?? 0,
          tint: _values['correction.tint'] ?? 0,
          highlights: _values['correction.highlights'] ?? 0,
          shadows: _values['correction.shadows'] ?? 0,
          hue: _values['correction.hue'] ?? 0,
          colorBoost: _values['correction.colorBoost'] ?? 0,
        ),
      );
    }
    for (final type in DigitorNodeEffectType.values) {
      final amount = _values['effect.${type.name}'];
      if (amount != null && amount != 0) {
        _w.addEffect(DigitorNodeEffect(type: type, amount: amount));
      }
    }
    if (_values.containsKey('window.feather') ||
        _flags.containsKey('window.invert')) {
      _w.addPowerWindow(
        DigitorPowerWindow(
          feather: _values['window.feather'] ?? 0.1,
          invert: _flags['window.invert'] ?? false,
        ),
      );
    }
    _emitSnapshot(message: 'Recipe ${_w.recipeIdentity}');
  }

  Future<void> _exportCurrentMedia() async {
    final media = _w.media;
    if (media == null || _mediaPath == null) {
      throw StateError('Import media before export.');
    }
    if (!_w.productionReady) {
      throw StateError('Native production host is not registered for export.');
    }

    FileSaveLocation? location;
    try {
      location = await getSaveLocation(suggestedName: 'digitor-export.mp4');
    } on UnsupportedError {
      location = null;
    }
    if (location == null) {
      _event('exportLocationRequired', const <String, Object?>{});
      return;
    }

    final status = _w.timelineStatus();
    final frameDurationUs = media.firstFrame.duration.inMicroseconds > 0
        ? media.firstFrame.duration.inMicroseconds
        : 33333;
    final lastFrame = status.durationUs > 0
        ? (status.durationUs / frameDurationUs)
            .ceil()
            .clamp(0, 1 << 30)
            .toInt()
        : media.firstFrame.frameNumber;

    _progressController.add(
      const EngineProgress(operation: 'export', fraction: 0),
    );
    _w.exportMedia(
      path: location.path,
      firstFrame: media.firstFrame.frameNumber,
      lastFrame: lastFrame,
      width: media.firstFrame.width,
      height: media.firstFrame.height,
      onProgress: (progress) {
        if (!_disposed) {
          _progressController.add(
            EngineProgress(operation: 'export', fraction: progress.fraction),
          );
        }
      },
    );
    _event('exportCompleted', <String, Object?>{'path': location.path});
  }

  void _emitDiagnostics() {
    final renderer = _w.renderer;
    final status = _w.timelineStatus();
    final telemetry = _w.timelineTelemetry();
    _event('diagnostics', <String, Object?>{
      'backend': renderer.backendName,
      'device': renderer.deviceName,
      'gpu': renderer.isGpu,
      'compute': renderer.supportsCompute,
      'fp16': renderer.supportsFp16,
      'fp32': renderer.supportsFp32,
      'timelineRevision': status.revision,
      'graphRevision': _w.graphRevision,
      'parameterRevision': _w.parameterRevision,
      'recipeIdentity': _w.recipeIdentity,
      'timelinePublications': telemetry.publications,
      'productionHostRegistered': _w.productionHostRegistered,
      'productionReady': _w.productionReady,
    });
  }

  void _emitSnapshot({String? message}) {
    if (_disposed || _workspace == null) return;
    final status = _w.timelineStatus();
    _snapshotController.add(
      EngineSnapshot(
        connected: true,
        projectOpen: _projectOpen,
        isPlaying: status.playbackState == DigitorPlaybackState.playing,
        position: Duration(microseconds: status.positionUs),
        duration: Duration(microseconds: status.durationUs),
        state: <String, Object?>{
          'backend': _w.renderer.backendName,
          'device': _w.renderer.deviceName,
          'isGpu': _w.renderer.isGpu,
          'mediaPath': _mediaPath,
          'recipeIdentity': _w.recipeIdentity,
          'graphRevision': _w.graphRevision,
          'parameterRevision': _w.parameterRevision,
          'productionHostRegistered': _w.productionHostRegistered,
          'productionReady': _w.productionReady,
        },
        engineMessage: message,
      ),
    );
  }

  void _event(String type, Map<String, Object?> payload) {
    if (!_disposed) _eventController.add(EngineEvent(type, payload));
  }

  void _eventUnsupported(String action) {
    _event('unsupportedAction', <String, Object?>{'action': action});
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _statusTimer?.cancel();
    final workspace = _workspace;
    _workspace = null;
    if (workspace != null) await workspace.close();
    await _snapshotController.close();
    await _progressController.close();
    await _eventController.close();
  }
}
