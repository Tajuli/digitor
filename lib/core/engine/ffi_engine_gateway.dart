import 'dart:async';
import 'dart:math' as math;

import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'engine_feature_catalog.dart';
import 'engine_gateway.dart';

/// Direct DigitorEngine integration. Flutter owns UI state only; decode,
/// rendering, grading, node execution, playback and export remain in Engine.
final class DigitorFfiEngineGateway implements EngineGateway {
  static const MethodChannel _androidExportChannel =
      MethodChannel('digitor_engine_ffi/platform_host');

  final _snapshotController = StreamController<EngineSnapshot>.broadcast();
  final _progressController = StreamController<EngineProgress>.broadcast();
  final _eventController = StreamController<EngineEvent>.broadcast();

  DigitorEditorWorkspace? _workspace;
  Timer? _statusTimer;
  bool _disposed = false;
  bool _projectOpen = false;
  bool _previewInFlight = false;
  bool _exportPreparing = false;
  bool _exportRequested = false;
  bool _exportInFlight = false;
  Future<void>? _activePreview;
  Future<void> _recipeMutationTail = Future<void>.value();
  int _recipeRequestSerial = 0;
  int _recipeAppliedSerial = 0;
  int _mediaImportSerial = 0;
  String? _mediaPath;
  int? _previewTextureId;
  int _previewWidth = 0;
  int _previewHeight = 0;
  int _lastPreviewPositionUs = -1;
  int _lastPreviewGraphRevision = -1;
  int _lastPreviewParameterRevision = -1;
  int _projectWidth = 0;
  int _projectHeight = 0;
  int _projectFpsNum = 30;
  int _projectFpsDen = 1;
  DigitorExportFormat _exportFormat = DigitorExportFormat.mp4;
  DigitorVideoCodec _exportCodec = DigitorVideoCodec.h264;

  final Map<String, double> _values = <String, double>{};
  final Map<String, bool> _flags = <String, bool>{};
  final Map<String, List<DigitorCurvePoint>> _curvePoints =
      <String, List<DigitorCurvePoint>>{
    'master': <DigitorCurvePoint>[
      const DigitorCurvePoint(0, 0),
      const DigitorCurvePoint(1, 1),
    ],
    'red': <DigitorCurvePoint>[
      const DigitorCurvePoint(0, 0),
      const DigitorCurvePoint(1, 1),
    ],
    'green': <DigitorCurvePoint>[
      const DigitorCurvePoint(0, 0),
      const DigitorCurvePoint(1, 1),
    ],
    'blue': <DigitorCurvePoint>[
      const DigitorCurvePoint(0, 0),
      const DigitorCurvePoint(1, 1),
    ],
  };

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
      installEngineTimelinePublisher((timeline) {
        unawaited(_configureProductionTimeline(timeline));
      });
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
      installEngineTimelinePublisher(null);
      _debug('initialize failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> _pollEngine() async {
    if (_disposed || _workspace == null) return;
    _emitSnapshot();
    if (_mediaPath == null ||
        !_w.productionReady ||
        _previewInFlight ||
        _exportPreparing ||
        _exportRequested ||
        _exportInFlight) {
      return;
    }
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

  Future<void> _renderPreview({bool force = false}) {
    final active = _activePreview;
    if (active != null) return active;
    if (_disposed ||
        _mediaPath == null ||
        !_w.productionReady ||
        _exportRequested ||
        _exportInFlight) {
      return Future<void>.value();
    }

    late final Future<void> task;
    task = _renderPreviewImpl(force: force).whenComplete(() {
      if (identical(_activePreview, task)) {
        _activePreview = null;
      }
    });
    _activePreview = task;
    return task;
  }

  Future<void> _renderPreviewImpl({required bool force}) async {
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
      final graphRevision = _w.graphRevision;
      final parameterRevision = _w.parameterRevision;
      final width = _projectWidth > 0 ? _projectWidth : media.firstFrame.width;
      final height = _projectHeight > 0 ? _projectHeight : media.firstFrame.height;
      final preview = await _w.presentPreview(
        timestampUs: status.positionUs,
        width: width,
        height: height,
      );
      _previewTextureId = preview.textureId;
      _previewWidth = preview.width;
      _previewHeight = preview.height;
      _lastPreviewPositionUs = preview.timestampUs;
      _lastPreviewGraphRevision = graphRevision;
      _lastPreviewParameterRevision = parameterRevision;
      _debug(
        'preview generation=${preview.generation} texture=${preview.textureId} '
        '${preview.width}x${preview.height} t=${preview.timestampUs} '
        'projectTimeline=${_w.productionTimelineConfigured} '
        'graph=$graphRevision params=$parameterRevision',
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
      'export.format',
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
        if (_workspace != null) await _w.releaseProductionSession();
        _projectOpen = true;
        _mediaPath = null;
        _mediaImportSerial = 0;
        _projectWidth = 0;
        _projectHeight = 0;
        _projectFpsNum = 30;
        _projectFpsDen = 1;
        _previewTextureId = null;
        _values.clear();
        _flags.clear();
        _resetCurves();
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

      if (action == 'color.primaryWheels.setWheel' && value is Map) {
        final name = value['name']?.toString();
        if (name == null ||
            !const <String>{'lift', 'gamma', 'gain', 'offset'}.contains(name)) {
          throw ArgumentError.value(name, 'name', 'Invalid Primary Wheels range.');
        }
        final r = value['r'];
        final g = value['g'];
        final b = value['b'];
        final master = value['master'];
        if (r is! num || g is! num || b is! num || master is! num) {
          throw ArgumentError('Primary Wheels batch values must be numeric.');
        }
        final rv = r.toDouble();
        final gv = g.toDouble();
        final bv = b.toDouble();
        final mv = master.toDouble();
        if (!rv.isFinite || !gv.isFinite || !bv.isFinite || !mv.isFinite) {
          throw ArgumentError('Primary Wheels batch values must be finite.');
        }
        _values['primary.${name}R'] = rv;
        _values['primary.${name}G'] = gv;
        _values['primary.${name}B'] = bv;
        _values['primary.${name}Master'] = mv;
        _flags['primary.enabled'] = true;
        await _rebuildSelectedOperations();
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

      if (action == 'color.logWheels.setWheel' && value is Map) {
        final range = value['range']?.toString();
        if (range == null ||
            !const <String>{'shadows', 'midtones', 'highlights', 'global'}
                .contains(range)) {
          throw ArgumentError.value(range, 'range', 'Invalid Log Wheels range.');
        }
        final r = value['r'];
        final g = value['g'];
        final b = value['b'];
        final master = value['master'];
        if (r is! num || g is! num || b is! num || master is! num) {
          throw ArgumentError('Log Wheels batch values must be numeric.');
        }
        final rv = r.toDouble();
        final gv = g.toDouble();
        final bv = b.toDouble();
        final mv = master.toDouble();
        if (!rv.isFinite || !gv.isFinite || !bv.isFinite || !mv.isFinite) {
          throw ArgumentError('Log Wheels batch values must be finite.');
        }
        _values['log.$range.r'] = rv;
        _values['log.$range.g'] = gv;
        _values['log.$range.b'] = bv;
        _values['log.$range.master'] = mv;
        _flags['log.enabled'] = true;
        await _rebuildSelectedOperations();
        return;
      }

      if (action == 'color.logWheels.reset') {
        _flags.remove('log.enabled');
        _values.removeWhere((key, _) => key.startsWith('log.'));
        await _rebuildSelectedOperations();
        return;
      }
      if (action == 'color.logWheels.open') {
        _flags['log.enabled'] = true;
        await _rebuildSelectedOperations();
        return;
      }
      if (action.startsWith('color.logWheels.') && value is num) {
        final key = action.substring('color.logWheels.'.length);
        _values['log.$key'] = value.toDouble();
        _flags['log.enabled'] = true;
        await _rebuildSelectedOperations();
        return;
      }

      if (action == 'color.rgbCurves.reset') {
        _resetCurves();
        _flags['curves.enabled'] = true;
        await _rebuildSelectedOperations();
        return;
      }
      if (action == 'color.rgbCurves.points') {
        _setCurvePoints(value);
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

      if (action == 'export.format.profile' && value is String) {
        switch (value) {
          case 'MP4 · H.264':
            _exportFormat = DigitorExportFormat.mp4;
            _exportCodec = DigitorVideoCodec.h264;
            break;
          case 'MP4 · H.265 (HEVC)':
            _exportFormat = DigitorExportFormat.mp4;
            _exportCodec = DigitorVideoCodec.h265;
            break;
          default:
            throw ArgumentError.value(
              value, 'value', 'Unsupported production export profile.');
        }
        _event('exportProfileChanged', <String, Object?>{
          'format': _exportFormat.name,
          'codec': _exportCodec.name,
          'profile': value,
        });
        _emitSnapshot(message: 'Export profile $value');
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

  Future<void> _configureProductionTimeline(
    Map<String, Object?> payload,
  ) async {
    if (_disposed || _workspace == null) return;
    try {
      final serialized = payload['serializedProject'];
      final revision = payload['revision'];
      final durationUs = payload['durationUs'];
      final videoTrackCount = payload['videoTrackCount'];
      final audioTrackCount = payload['audioTrackCount'];
      final fpsNum = payload['fpsNum'];
      final fpsDen = payload['fpsDen'];
      final rawSources = payload['sources'];
      if (serialized is! String || serialized.isEmpty ||
          revision is! num || durationUs is! num ||
          videoTrackCount is! num || audioTrackCount is! num ||
          fpsNum is! num || fpsDen is! num || rawSources is! List) {
        throw ArgumentError('Mobile timeline publication is incomplete.');
      }

      final sources = <DigitorTimelineMediaSource>[];
      for (final raw in rawSources) {
        if (raw is! Map) {
          throw ArgumentError('Timeline source registry entry is invalid.');
        }
        final group = raw['sourceMediaGroupId']?.toString() ?? '';
        final path = raw['path']?.toString() ?? '';
        if (group.isEmpty || path.isEmpty) {
          throw ArgumentError('Timeline source id/path is missing.');
        }
        sources.add(
          DigitorTimelineMediaSource(
            sourceMediaGroupId: group,
            path: path,
          ),
        );
      }
      final activePreview = _activePreview;
      if (activePreview != null) await activePreview;
      if (_disposed) return;

      final media = _w.media;
      if (media == null) {
        throw StateError('Import media before publishing the project timeline.');
      }
      if (_projectWidth == 0 || _projectHeight == 0) {
        _projectWidth = media.firstFrame.width;
        _projectHeight = media.firstFrame.height;
      }
      _projectFpsNum = fpsNum.toInt();
      _projectFpsDen = fpsDen.toInt();
      _w.configureProductionTimeline(
        serializedProject: serialized,
        sources: sources,
        revision: revision.toInt(),
        durationUs: durationUs.toInt(),
        videoTrackCount: videoTrackCount.toInt(),
        audioTrackCount: audioTrackCount.toInt(),
        fpsNum: _projectFpsNum,
        fpsDen: _projectFpsDen,
      );
      final requestedPosition = payload['positionUs'];
      if (requestedPosition is num) {
        _w.seek(requestedPosition.toInt());
      }
      _lastPreviewPositionUs = -1;
      _lastPreviewGraphRevision = -1;
      _lastPreviewParameterRevision = -1;
      _emitSnapshot(message: 'Project timeline ${revision.toInt()}');
      await _renderPreview(force: true);
    } catch (error, stack) {
      _debug('timeline configure failed: $error\n$stack');
      _event('engineError', <String, Object?>{
        'action': 'timeline.project.configure',
        'error': '$error',
      });
    }
  }

  Future<void> _importMedia() async {
    late final String mediaPath;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final selected = await _androidExportChannel.invokeMapMethod<String, Object?>(
        'pickMediaImport',
      );
      if (selected == null) return;
      final path = selected['path'];
      if (path is! String || path.trim().isEmpty) {
        throw StateError('Android media picker returned no staged file path.');
      }
      mediaPath = path.trim();
      _debug(
        'Android media staged path=$mediaPath '
        'name=${selected['displayName']} size=${selected['size']} '
        'mime=${selected['mimeType']}',
      );
    } else {
      final file = await openFile();
      if (file == null) return;
      mediaPath = file.path;
    }

    _debug('opening $mediaPath');
    final media = _w.openMedia(mediaPath);
    _mediaPath = mediaPath;
    _mediaImportSerial += 1;
    _projectOpen = true;
    if (_projectWidth == 0 || _projectHeight == 0) {
      _projectWidth = media.firstFrame.width;
      _projectHeight = media.firstFrame.height;
    }
    _lastPreviewPositionUs = -1;
    _lastPreviewGraphRevision = -1;
    _lastPreviewParameterRevision = -1;
    _emitSnapshot(message: 'Media opened');
    _event('mediaOpened', <String, Object?>{
      'path': media.path,
      'importSerial': _mediaImportSerial,
      'decoder': media.decoder.implementation,
      'hardwareAccelerated': media.decoder.hardwareAccelerated,
      'nativeSurfaceOutput': media.decoder.nativeSurfaceOutput,
      'strictGpuPath': media.strictGpuPath,
      'durationUs': media.duration.inMicroseconds,
      'frameDurationUs': media.firstFrame.duration.inMicroseconds,
      'width': media.firstFrame.width,
      'height': media.firstFrame.height,
      'pixelFormat': media.firstFrame.pixelFormat.name,
      'gpuResident': media.firstFrame.gpuResident,
      'cpuResident': media.firstFrame.cpuResident,
    });
    _debug(
      'media durationUs=${media.duration.inMicroseconds} '
      'frameDurationUs=${media.firstFrame.duration.inMicroseconds}',
    );
    // For subsequent imports the mobile timeline immediately republishes the
    // full project and that render is authoritative. Avoid doing redundant
    // single-source preview work between import and project publication.
    if (_mediaImportSerial == 1) {
      await _renderPreview(force: true);
    }
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
        final stepUs = _projectFpsNum > 0
            ? (1000000 * _projectFpsDen / _projectFpsNum).round()
            : 33333;
        _w.seek((status.positionUs - stepUs).clamp(0, 1 << 62).toInt());
        break;
      case 'playback.transport.nextFrame':
        final stepUs = _projectFpsNum > 0
            ? (1000000 * _projectFpsDen / _projectFpsNum).round()
            : 33333;
        _w.seek((status.positionUs + stepUs).clamp(0, 1 << 62).toInt());
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

  DigitorLogWheel _logWheel(String name) => DigitorLogWheel(
        rgb: DigitorRgb(
          _values['log.$name.r'] ?? 0,
          _values['log.$name.g'] ?? 0,
          _values['log.$name.b'] ?? 0,
        ),
        master: _values['log.$name.master'] ?? 0,
      );

  DigitorLogWheels _logWheels() {
    final rawShadow =
        (_values['log.shadowPivot'] ?? 0.33).clamp(0.05, 0.60).toDouble();
    final rawHighlight =
        (_values['log.highlightPivot'] ?? 0.67).clamp(0.40, 0.95).toDouble();
    final shadow = math
        .min(rawShadow, rawHighlight - 0.01)
        .clamp(0.05, 0.60)
        .toDouble();
    final highlight = math
        .max(rawHighlight, shadow + 0.01)
        .clamp(0.40, 0.95)
        .toDouble();
    return DigitorLogWheels(
      shadows: _logWheel('shadows'),
      midtones: _logWheel('midtones'),
      highlights: _logWheel('highlights'),
      global: _logWheel('global'),
      shadowPivot: shadow,
      highlightPivot: highlight,
      transitionWidth: (_values['log.transitionWidth'] ?? 0.10)
          .clamp(0.01, 0.30)
          .toDouble(),
    );
  }

  void _resetCurves() {
    for (final channel in const <String>['master', 'red', 'green', 'blue']) {
      _curvePoints[channel] = <DigitorCurvePoint>[
        const DigitorCurvePoint(0, 0),
        const DigitorCurvePoint(1, 1),
      ];
    }
  }

  void _setCurvePoints(Object? value) {
    if (value is! Map) {
      throw ArgumentError('RGB curve point payload must be a map.');
    }
    final channel = value['channel']?.toString().toLowerCase();
    if (!_curvePoints.containsKey(channel)) {
      throw ArgumentError('RGB curve channel is invalid: $channel');
    }
    final rawPoints = value['points'];
    if (rawPoints is! List || rawPoints.length < 2) {
      throw ArgumentError('RGB curve requires at least two points.');
    }
    final parsed = <DigitorCurvePoint>[];
    for (final raw in rawPoints) {
      if (raw is! Map || raw['x'] is! num || raw['y'] is! num) {
        throw ArgumentError('RGB curve point must contain numeric x/y values.');
      }
      final x = (raw['x'] as num).toDouble();
      final y = (raw['y'] as num).toDouble();
      if (!x.isFinite || !y.isFinite) {
        throw ArgumentError('RGB curve point values must be finite.');
      }
      parsed.add(
        DigitorCurvePoint(
          x.clamp(0.0, 1.0).toDouble(),
          y.clamp(0.0, 1.0).toDouble(),
        ),
      );
    }
    parsed.sort((a, b) => a.x.compareTo(b.x));
    parsed[0] = DigitorCurvePoint(0, parsed.first.y);
    parsed[parsed.length - 1] = DigitorCurvePoint(1, parsed.last.y);
    for (var i = 1; i < parsed.length; i++) {
      if (parsed[i].x <= parsed[i - 1].x) {
        throw ArgumentError('RGB curve x positions must be strictly increasing.');
      }
    }
    _curvePoints[channel!] = List<DigitorCurvePoint>.unmodifiable(parsed);
  }

  DigitorRgbCurves _rgbCurves() => DigitorRgbCurves(
        master: DigitorCurveChannel(points: _curvePoints['master']!),
        red: DigitorCurveChannel(points: _curvePoints['red']!),
        green: DigitorCurveChannel(points: _curvePoints['green']!),
        blue: DigitorCurveChannel(points: _curvePoints['blue']!),
      );

  Future<void> _rebuildSelectedOperations() {
    final requestedSerial = ++_recipeRequestSerial;
    final previous = _recipeMutationTail;
    final scheduled = previous.catchError((Object _) {}).then((_) async {
      if (_disposed || requestedSerial != _recipeRequestSerial) return;

      final preview = _activePreview;
      if (preview != null) await preview;
      if (_disposed || requestedSerial != _recipeRequestSerial) return;

      if (_exportRequested || _exportInFlight) return;

      _applySelectedOperations();
      _recipeAppliedSerial = requestedSerial;
      _emitSnapshot(message: 'Recipe ${_w.recipeIdentity}');
      await _renderPreview(force: true);
    });
    _recipeMutationTail = scheduled;
    return scheduled;
  }

  void _applySelectedOperations() {
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
      _w.addLogWheels(_logWheels());
    }
    if (_flags['curves.enabled'] == true) {
      _w.addRgbCurves(_rgbCurves());
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
    if (_values.containsKey('window.feather') ||
        _flags.containsKey('window.invert')) {
      _w.addPowerWindow(
        DigitorPowerWindow(
          feather: _values['window.feather'] ?? 0.1,
          invert: _flags['window.invert'] ?? false,
        ),
      );
    }
  }

  String _normalizedExportPath(String path) {
    const extension = '.mp4';
    if (path.toLowerCase().endsWith(extension)) return path;
    final separator = math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    final dot = path.lastIndexOf('.');
    if (dot > separator) return '${path.substring(0, dot)}$extension';
    return '$path$extension';
  }

  Future<String?> _pickExportPath() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final target = await _androidExportChannel.invokeMapMethod<String, Object?>(
        'prepareExport',
        const <String, Object>{'displayName': 'digitor-export.mp4'},
      );
      final stagingPath = target?['stagingPath'];
      if (stagingPath is! String || stagingPath.trim().isEmpty) {
        throw StateError('Android export staging path is unavailable.');
      }
      _debug(
        'Android export staging=${stagingPath.trim()} '
        'collection=${target?['collection']}',
      );
      return _normalizedExportPath(stagingPath.trim());
    }

    FileSaveLocation? location;
    try {
      location = await getSaveLocation(suggestedName: 'digitor-export.mp4');
    } on UnsupportedError {
      location = null;
    }
    if (location == null) return null;
    return _normalizedExportPath(location.path);
  }

  Future<String> _publishAndroidExport(String stagingPath) async {
    final published = await _androidExportChannel.invokeMapMethod<String, Object?>(
      'publishExport',
      <String, Object>{'stagingPath': stagingPath},
    );
    if (published == null) {
      throw StateError('Android MediaStore returned no published export.');
    }
    final displayPath = published['displayPath'];
    final uri = published['uri'];
    final visiblePath = displayPath is String && displayPath.trim().isNotEmpty
        ? displayPath.trim()
        : uri is String && uri.trim().isNotEmpty
            ? uri.trim()
            : null;
    if (visiblePath == null) {
      throw StateError('Android MediaStore returned no export location.');
    }
    _debug('Android export published path=$visiblePath uri=$uri');
    return visiblePath;
  }

  Future<void> _discardAndroidExport(String stagingPath) async {
    try {
      await _androidExportChannel.invokeMethod<void>(
        'discardExport',
        <String, Object>{'stagingPath': stagingPath},
      );
    } catch (error) {
      _debug('Android export staging cleanup failed: $error');
    }
  }

  Future<void> _exportCurrentMedia() async {
    if (_exportPreparing || _exportRequested || _exportInFlight) {
      _debug('duplicate export request ignored while export is active');
      return;
    }
    _exportPreparing = true;
    try {
      await _recipeMutationTail.catchError((Object _) {});
      final preview = _activePreview;
      if (preview != null) await preview;
      _exportRequested = true;
      _exportPreparing = false;
      _exportInFlight = true;
      final media = _w.media;
      if (media == null || _mediaPath == null) {
        throw StateError('Import media before export.');
      }
      if (!_w.productionReady) {
        throw StateError('Native production host is not registered for export.');
      }

      final outputPath = await _pickExportPath();
      if (outputPath == null) {
        _event('exportLocationRequired', const <String, Object?>{});
        return;
      }

      final status = _w.timelineStatus();
      final projectTimeline = _w.productionTimelineConfigured;
      final durationUs = status.durationUs > 0
          ? status.durationUs
          : media.duration.inMicroseconds;
      if (durationUs <= 0) {
        throw StateError('Native timeline duration is unavailable for full export.');
      }

      late final int firstFrame;
      late final int frameCount;
      if (projectTimeline) {
        final denominator = 1000000 * _projectFpsDen;
        frameCount = ((durationUs * _projectFpsNum + denominator - 1) ~/ denominator)
            .clamp(1, 1 << 30)
            .toInt();
        firstFrame = 0;
      } else {
        final frameDurationUs = media.firstFrame.duration.inMicroseconds > 0
            ? media.firstFrame.duration.inMicroseconds
            : 33333;
        frameCount = ((durationUs + frameDurationUs - 1) ~/ frameDurationUs)
            .clamp(1, 1 << 30)
            .toInt();
        firstFrame = media.firstFrame.frameNumber;
      }
      final lastFrame = firstFrame + frameCount - 1;
      final width = _projectWidth > 0 ? _projectWidth : media.firstFrame.width;
      final height = _projectHeight > 0 ? _projectHeight : media.firstFrame.height;
      _debug(
        'export destination=$outputPath durationUs=$durationUs '
        'timelineDurationUs=${status.durationUs} projectTimeline=$projectTimeline '
        'fps=$_projectFpsNum/$_projectFpsDen range=$firstFrame..$lastFrame '
        'size=${width}x$height codec=${_exportCodec.name}',
      );

      _event('exportStarted', <String, Object?>{
        'path': outputPath,
        'frames': frameCount,
        'durationUs': durationUs,
        'projectTimeline': projectTimeline,
        'format': _exportFormat.name,
        'codec': _exportCodec.name,
      });
      _progressController.add(
        const EngineProgress(operation: 'export', fraction: 0),
      );
      await Future<void>.delayed(Duration.zero);

      var nativeExportCompleted = false;
      try {
        _w.exportMedia(
          path: outputPath,
          firstFrame: firstFrame,
          lastFrame: lastFrame,
          width: width,
          height: height,
          format: _exportFormat,
          codec: _exportCodec,
          onProgress: (progress) {
            if (!_disposed) {
              _progressController.add(
                EngineProgress(
                  operation: 'export',
                  fraction: progress.fraction,
                ),
              );
            }
          },
        );
        nativeExportCompleted = true;

        final publishedPath = defaultTargetPlatform == TargetPlatform.android
            ? await _publishAndroidExport(outputPath)
            : outputPath;
        if (!_disposed) {
          _progressController.add(
            const EngineProgress(operation: 'export', fraction: 1),
          );
        }
        _debug(
          'export completed $publishedPath '
          'format=${_exportFormat.name} codec=${_exportCodec.name}',
        );
        _event('exportCompleted', <String, Object?>{
          'path': publishedPath,
          'format': _exportFormat.name,
          'codec': _exportCodec.name,
        });
      } catch (_) {
        if (defaultTargetPlatform == TargetPlatform.android &&
            !nativeExportCompleted) {
          await _discardAndroidExport(outputPath);
        }
        rethrow;
      }
    } finally {
      _exportInFlight = false;
      _exportRequested = false;
      _exportPreparing = false;
      if (!_disposed && _recipeAppliedSerial != _recipeRequestSerial) {
        unawaited(_rebuildSelectedOperations());
      } else if (!_disposed) {
        unawaited(_renderPreview(force: true));
      }
    }
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
      'productionTimelineConfigured': _w.productionTimelineConfigured,
      'previewTextureId': _previewTextureId,
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
          'mediaImportSerial': _mediaImportSerial,
          'recipeIdentity': _w.recipeIdentity,
          'graphRevision': _w.graphRevision,
          'parameterRevision': _w.parameterRevision,
          'productionHostRegistered': _w.productionHostRegistered,
          'productionReady': _w.productionReady,
          'productionTimelineConfigured': _w.productionTimelineConfigured,
          'projectWidth': _projectWidth,
          'projectHeight': _projectHeight,
          'projectFpsNum': _projectFpsNum,
          'projectFpsDen': _projectFpsDen,
          'previewTextureId': _previewTextureId,
          'previewWidth': _previewWidth,
          'previewHeight': _previewHeight,
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
    installEngineTimelinePublisher(null);
    _statusTimer?.cancel();
    final workspace = _workspace;
    _workspace = null;
    if (workspace != null) await workspace.close();
    await _snapshotController.close();
    await _progressController.close();
    await _eventController.close();
  }
}
