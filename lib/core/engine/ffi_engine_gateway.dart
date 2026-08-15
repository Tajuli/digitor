import 'dart:async';

import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'engine_feature_catalog.dart';
import 'engine_gateway.dart';

/// Direct DigitorEngine integration. Flutter owns UI state only; decode,
/// rendering, grading, node execution, playback and export remain in Engine.
final class DigitorFfiEngineGateway implements EngineGateway {
  final _snapshotController = StreamController<EngineSnapshot>.broadcast();
  final _progressController = StreamController<EngineProgress>.broadcast();
  final _eventController = StreamController<EngineEvent>.broadcast();

  DigitorEditorWorkspace? _workspace;
  Timer? _statusTimer;
  bool _disposed = false;
  bool _projectOpen = false;
  bool _previewInFlight = false;
  String? _mediaPath;
  int? _previewTextureId;
  int _previewWidth = 0;
  int _previewHeight = 0;
  int _previewGeneration = 0;
  int _lastPreviewPositionUs = -1;
  int _lastPreviewGraphRevision = -1;
  int _lastPreviewParameterRevision = -1;

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
    try {
      final workspace = await DigitorEditorWorkspace.create();
      _workspace = workspace;
      _statusTimer = Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => unawaited(_pollEngine()),
      );
      _emitSnapshot(message: 'DigitorEngine ready');
      _debug(
        'ready backend=${workspace.renderer.backendName} '
        'device=${workspace.renderer.deviceName} '
        'host=${workspace.hostCapabilities?.platform} '
        'productionHost=${workspace.productionHostRegistered}',
      );
      _event('engineReady', <String, Object?>{
        'engineVersion': DigitorEngine.version,
        'backend': workspace.renderer.backendName,
        'device': workspace.renderer.deviceName,
        'gpu': workspace.renderer.isGpu,
        'productionHostRegistered': workspace.productionHostRegistered,
        'platformHost': workspace.hostCapabilities?.platform,
      });
    } catch (error, stack) {
      _debug('initialize failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> _pollEngine() async {
    if (_disposed || _workspace == null) return;
    _emitSnapshot();
    if (_mediaPath == null || !_w.productionReady || _previewInFlight) return;
    final status = _w.timelineStatus();
    final graphChanged = _lastPreviewGraphRevision != _w.graphRevision ||
        _lastPreviewParameterRevision != _w.parameterRevision;
    final positionChanged = _lastPreviewPositionUs != status.positionUs;
    if (status.playbackState == DigitorPlaybackState.playing ||
        graphChanged ||
        positionChanged ||
        _previewTextureId == null) {
      await _renderPreview();
    }
  }

  Future<void> _renderPreview({bool force = false}) async {
    if (_disposed || _previewInFlight || _mediaPath == null || !_w.productionReady) {
      return;
    }
    final media = _w.media;
    if (media == null) return;
    final status = _w.timelineStatus();
    if (!force &&
        _previewTextureId != null &&
        _lastPreviewPositionUs == status.positionUs &&
        _lastPreviewGraphRevision == _w.graphRevision &&
        _lastPreviewParameterRevision == _w.parameterRevision) {
      return;
    }

    _previewInFlight = true;
    try {
      final preview = await _w.presentPreview(
        timestampUs: status.positionUs,
        width: media.firstFrame.width,
        height: media.firstFrame.height,
      );
      _previewTextureId = preview.textureId;
      _previewWidth = preview.width;
      _previewHeight = preview.height;
      _previewGeneration = preview.generation;
      _lastPreviewPositionUs = preview.timestampUs;
      _lastPreviewGraphRevision = _w.graphRevision;
      _lastPreviewParameterRevision = _w.parameterRevision;
      _debug(
        'preview generation=${preview.generation} texture=${preview.textureId} '
        '${preview.width}x${preview.height} t=${preview.timestampUs}',
      );
      _emitSnapshot(message: 'Preview frame ${preview.generation}');
    } catch (error, stack) {
      _debug('preview failed: $error\n$stack');
      _event('previewError', <String, Object?>{'error': '$error'});
    } finally {
      _previewInFlight = false;
    }
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
      'project.lifecycle',
      'media.import',
      'media.decode',
      'media.metadata',
      'media.zeroCopy',
      'color.correction',
      'color.primaryWheels',
      'color.logWheels',
      'color.rgbCurves',
      'color.hslQualifier',
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
      'timeline.speed',
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
    _debug('dispatch $action value=$value');
    try {
      if (action == 'media.import.requestPicker' || action == 'project.lifecycle.open') {
        await _importMedia();
        return;
      }
      if (action == 'project.lifecycle.new') {
        _projectOpen = true;
        _mediaPath = null;
        _previewTextureId = null;
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
          await _rebuildSelectedOperations();
        }
        return;
      }

      if (action == 'color.primaryWheels.reset') {
        _flags.remove('primary.enabled');
        _values.removeWhere((key, _) => key.startsWith('primary.'));
        await _rebuildSelectedOperations();
        return;
      }
      if (action == 'color.primaryWheels.open') {
        _flags['primary.enabled'] = true;
        await _rebuildSelectedOperations();
        return;
      }
      if (action.startsWith('color.primaryWheels.') && value is num) {
        final key = action.substring('color.primaryWheels.'.length);
        _values['primary.$key'] = value.toDouble();
        _flags['primary.enabled'] = true;
        await _rebuildSelectedOperations();
        return;
      }
      if (action == 'color.logWheels.reset') {
        _flags.remove('log.enabled');
        await _rebuildSelectedOperations();
        return;
      }
      if (action == 'color.logWheels.open') {
        _flags['log.enabled'] = true;
        await _rebuildSelectedOperations();
        return;
      }
      if (action == 'color.rgbCurves.reset') {
        _flags['curves.enabled'] = true;
        await _rebuildSelectedOperations();
        return;
      }
      if (action == 'color.rgbCurves.channel') {
        _event('curveChannelChanged', <String, Object?>{'channel': value});
        return;
      }
      if (action == 'color.hslQualifier.highlight' && value is bool) {
        _flags['qualifier.highlight'] = value;
        await _rebuildSelectedOperations();
        return;
      }

      if (action.startsWith('effects.masksWindows.')) {
        await _handleWindow(action, value);
        return;
      }
      if (action.startsWith('effects.')) {
        await _handleEffect(action, value);
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
        await _renderPreview(force: true);
        return;
      }

      if (action == 'nodes.connections.bypass' && value is bool) {
        _w.setSelectedBypassed(value);
        _emitSnapshot();
        await _renderPreview(force: true);
        return;
      }

      if (action.startsWith('playback.transport.')) {
        await _handleTransport(action, value);
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

      if (action == 'runtime.backend.inspect' || action == 'media.metadata.inspect') {
        _emitDiagnostics();
        return;
      }

      _eventUnsupported(action);
    } catch (error, stack) {
      _debug('dispatch failed $action: $error\n$stack');
      _event('engineError', <String, Object?>{'action': action, 'error': '$error'});
      rethrow;
    }
  }

  Future<void> _importMedia() async {
    final file = await openFile();
    if (file == null) return;
    _debug('opening ${file.path}');
    final media = _w.openMedia(file.path);
    _mediaPath = file.path;
    _projectOpen = true;
    _lastPreviewPositionUs = -1;
    _lastPreviewGraphRevision = -1;
    _lastPreviewParameterRevision = -1;
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
    await _renderPreview(force: true);
  }

  Future<void> _handleTransport(String action, Object? value) async {
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
    await _renderPreview(force: true);
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

  Future<void> _handleEffect(String action, Object? value) async {
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
    await _rebuildSelectedOperations();
  }

  Future<void> _handleWindow(String action, Object? value) async {
    if (action.endsWith('.feather') && value is num) {
      _values['window.feather'] = value.toDouble();
    } else if (action.endsWith('.invert') && value is bool) {
      _flags['window.invert'] = value;
    } else {
      _eventUnsupported(action);
      return;
    }
    await _rebuildSelectedOperations();
  }

  double _correctionValue(String key) {
    final value = _values['correction.$key'];
    if (value == null) return 0;
    switch (key) {
      case 'exposure':
        return value / 5.0;
      case 'saturation':
        return value - 1.0;
      case 'hue':
        return value / 180.0;
      default:
        return value;
    }
  }

  DigitorPrimaryWheel _primaryWheel(
    String name, {
    required double identityRgb,
    required double identityMaster,
  }) {
    return DigitorPrimaryWheel(
      rgb: DigitorRgb(
        _values['primary.${name}R'] ?? identityRgb,
        _values['primary.${name}G'] ?? identityRgb,
        _values['primary.${name}B'] ?? identityRgb,
      ),
      master: _values['primary.${name}Master'] ?? identityMaster,
    );
  }

  Future<void> _rebuildSelectedOperations() async {
    _w.clearSelectedOperations();
    if (_values.keys.any((key) => key.startsWith('correction.'))) {
      _w.addCorrection(
        DigitorCorrection(
          exposure: _correctionValue('exposure'),
          contrast: _correctionValue('contrast'),
          saturation: _correctionValue('saturation'),
          temperature: _correctionValue('temperature'),
          tint: _correctionValue('tint'),
          highlights: _correctionValue('highlights'),
          shadows: _correctionValue('shadows'),
          hue: _correctionValue('hue'),
          colorBoost: _correctionValue('colorBoost'),
        ),
      );
    }
    if (_flags['primary.enabled'] == true) {
      _w.addPrimaryWheels(
        DigitorPrimaryWheels(
          lift: _primaryWheel('lift', identityRgb: 0, identityMaster: 0),
          gamma: _primaryWheel('gamma', identityRgb: 1, identityMaster: 1),
          gain: _primaryWheel('gain', identityRgb: 1, identityMaster: 1),
          offset: _primaryWheel('offset', identityRgb: 0, identityMaster: 0),
        ),
      );
    }
    if (_flags['log.enabled'] == true) {
      _w.addLogWheels(const DigitorLogWheels());
    }
    if (_flags['curves.enabled'] == true) {
      _w.addRgbCurves(const DigitorRgbCurves());
    }
    if (_flags.containsKey('qualifier.highlight')) {
      _w.addHslQualifier(
        DigitorHslQualifier(matteOutput: _flags['qualifier.highlight'] ?? false),
      );
    }
    for (final type in DigitorNodeEffectType.values) {
      final amount = _values['effect.${type.name}'];
      if (amount != null && amount != 0) {
        _w.addEffect(DigitorNodeEffect(type: type, amount: amount));
      }
    }
    if (_values.containsKey('window.feather') || _flags.containsKey('window.invert')) {
      _w.addPowerWindow(
        DigitorPowerWindow(
          feather: _values['window.feather'] ?? 0.1,
          invert: _flags['window.invert'] ?? false,
        ),
      );
    }
    _emitSnapshot(message: 'Recipe ${_w.recipeIdentity}');
    await _renderPreview(force: true);
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
        ? (status.durationUs / frameDurationUs).ceil().clamp(0, 1 << 30).toInt()
        : media.firstFrame.frameNumber;

    _progressController.add(const EngineProgress(operation: 'export', fraction: 0));
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
      'previewTextureId': _previewTextureId,
      'previewGeneration': _previewGeneration,
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
          'previewTextureId': _previewTextureId,
          'previewWidth': _previewWidth,
          'previewHeight': _previewHeight,
          'previewGeneration': _previewGeneration,
        },
        engineMessage: message,
      ),
    );
  }

  void _event(String type, Map<String, Object?> payload) {
    if (!_disposed) _eventController.add(EngineEvent(type, payload));
  }

  void _eventUnsupported(String action) {
    _debug('unsupported action: $action');
    _event('unsupportedAction', <String, Object?>{'action': action});
  }

  void _debug(String message) {
    if (kDebugMode) debugPrint('[DigitorEngine] $message');
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
