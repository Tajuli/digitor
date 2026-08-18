import 'dart:async';

import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'engine_gateway.dart';
import 'ffi_engine_gateway.dart';

/// Startup-safe facade for the DigitorEngine-backed application gateway.
///
/// DigitorEngine's native runtime must be initialized before the Flutter
/// production host can be resolved. All UI commands also await the same
/// initialization future, so an early tap cannot reach the FFI gateway while
/// its workspace is still null.
final class BootstrappedDigitorEngineGateway implements EngineGateway {
  BootstrappedDigitorEngineGateway({DigitorFfiEngineGateway? inner})
      : _inner = inner ?? DigitorFfiEngineGateway() {
    _snapshotSubscription = _inner.snapshots.listen(
      _handleSnapshot,
      onError: _snapshotController.addError,
    );
  }

  static const MethodChannel _androidPreviewChannel =
      MethodChannel('digitor_engine_ffi/platform_host');

  final DigitorFfiEngineGateway _inner;
  final StreamController<EngineSnapshot> _snapshotController =
      StreamController<EngineSnapshot>.broadcast();
  StreamSubscription<EngineSnapshot>? _snapshotSubscription;
  Future<void>? _initializing;
  bool _initialized = false;
  bool _disposed = false;

  EngineSnapshot? _latestSnapshot;
  String? _sourcePreviewPath;
  String? _sourcePreviewCreatingPath;
  int? _sourcePreviewTextureId;
  int _sourcePreviewWidth = 0;
  int _sourcePreviewHeight = 0;
  bool _sourcePreviewPlaying = false;

  bool get _androidFallbackEnabled =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<EngineSnapshot> get snapshots => _snapshotController.stream;

  @override
  Stream<EngineProgress> get progress => _inner.progress;

  @override
  Stream<EngineEvent> get events => _inner.events;

  @override
  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.error(
        StateError('DigitorEngine gateway has been disposed.'),
      );
    }
    if (_initialized) return Future<void>.value();
    return _initializing ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    try {
      // Loading/initializing the engine first is required by the production
      // bootstrap contract. DigitorEditorWorkspace.create() inside the inner
      // gateway reuses this process-wide engine instance.
      final engine = DigitorEngine.initialize();
      final renderer = engine.rendererInfo;

      final bootstrap = await DigitorFlutterProductionBootstrap.resolve();
      if (kDebugMode) {
        debugPrint(
          '[DigitorEngine] bootstrap after engine init '
          'backend=${renderer.backendName} '
          'platform=${bootstrap.platform} '
          'textureHostReady=${bootstrap.textureHostReady} '
          'productionHostRegistered=${bootstrap.productionHostRegistered} '
          'ready=${bootstrap.ready} '
          'diagnostic=${bootstrap.diagnostic}',
        );
      }

      await _inner.initialize();
      _initialized = true;
    } catch (_) {
      // Allow Retry in the editor to make a fresh initialization attempt.
      _initializing = null;
      rethrow;
    }
  }

  void _handleSnapshot(EngineSnapshot snapshot) {
    if (_disposed) return;
    _latestSnapshot = snapshot;

    if (!_androidFallbackEnabled) {
      _snapshotController.add(snapshot);
      return;
    }

    final rawEngineTexture = snapshot.state['previewTextureId'];
    final engineTexture = rawEngineTexture is int ? rawEngineTexture : null;
    final mediaPath = snapshot.state['mediaPath']?.toString();

    // A real DigitorEngine production texture always wins. The fallback is
    // deliberately source-only and exists only while Android production host
    // registration is incomplete.
    if (engineTexture != null) {
      _snapshotController.add(snapshot);
      if (_sourcePreviewTextureId != null) {
        unawaited(_disposeSourcePreview());
      }
      return;
    }

    if (mediaPath == null || mediaPath.isEmpty) {
      _snapshotController.add(snapshot);
      if (_sourcePreviewTextureId != null) {
        unawaited(_disposeSourcePreview());
      }
      return;
    }

    if (_sourcePreviewTextureId != null && _sourcePreviewPath == mediaPath) {
      _snapshotController.add(_withSourcePreview(snapshot));
      return;
    }

    _snapshotController.add(snapshot);
    unawaited(_ensureSourcePreview(mediaPath));
  }

  EngineSnapshot _withSourcePreview(EngineSnapshot snapshot) {
    final textureId = _sourcePreviewTextureId;
    if (textureId == null) return snapshot;
    final state = Map<String, Object?>.from(snapshot.state)
      ..['previewTextureId'] = textureId
      ..['previewWidth'] = _sourcePreviewWidth
      ..['previewHeight'] = _sourcePreviewHeight
      ..['previewFallback'] = true;
    return EngineSnapshot(
      connected: snapshot.connected,
      projectOpen: snapshot.projectOpen,
      isPlaying: snapshot.isPlaying,
      position: snapshot.position,
      duration: snapshot.duration,
      state: state,
      engineMessage: snapshot.engineMessage,
    );
  }

  Future<void> _ensureSourcePreview(String path) async {
    if (_disposed || !_androidFallbackEnabled) return;
    if (_sourcePreviewTextureId != null && _sourcePreviewPath == path) return;
    if (_sourcePreviewCreatingPath == path) return;

    _sourcePreviewCreatingPath = path;
    await _disposeSourcePreview();
    try {
      final response = await _androidPreviewChannel
          .invokeMapMethod<String, Object?>('createSourcePreview', <String, Object>{
        'path': path,
      });
      final rawTextureId = response?['textureId'];
      final textureId = rawTextureId is int ? rawTextureId : null;
      final width = response?['width'];
      final height = response?['height'];
      if (textureId == null || textureId < 0 || width is! int || height is! int) {
        throw StateError('Android source preview returned invalid texture metadata.');
      }

      final latestPath = _latestSnapshot?.state['mediaPath']?.toString();
      if (_disposed || latestPath != path) {
        await _disposeNativeSourcePreview(textureId);
        return;
      }

      _sourcePreviewTextureId = textureId;
      _sourcePreviewPath = path;
      _sourcePreviewWidth = width;
      _sourcePreviewHeight = height;

      final latest = _latestSnapshot;
      if (latest != null) {
        await _syncSourcePreview(latest);
        if (!_disposed && _sourcePreviewTextureId == textureId) {
          _snapshotController.add(_withSourcePreview(latest));
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[DigitorEngine] Android source preview fallback ready '
          'texture=$textureId ${width}x$height',
        );
      }
    } on MissingPluginException catch (error) {
      if (kDebugMode) {
        debugPrint('[DigitorEngine] Android source preview plugin unavailable: $error');
      }
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[DigitorEngine] Android source preview failed '
          '${error.code}: ${error.message}',
        );
      }
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[DigitorEngine] Android source preview failed: $error\n$stack');
      }
    } finally {
      if (_sourcePreviewCreatingPath == path) {
        _sourcePreviewCreatingPath = null;
      }
    }
  }

  Future<void> _syncSourcePreview(EngineSnapshot snapshot) async {
    final textureId = _sourcePreviewTextureId;
    if (textureId == null) return;
    await _androidPreviewChannel.invokeMethod<void>(
      'sourcePreviewSeek',
      <String, Object>{
        'textureId': textureId,
        'positionMs': snapshot.position.inMilliseconds,
      },
    );
    if (snapshot.isPlaying) {
      await _androidPreviewChannel.invokeMethod<void>(
        'sourcePreviewPlay',
        <String, Object>{'textureId': textureId},
      );
    } else {
      await _androidPreviewChannel.invokeMethod<void>(
        'sourcePreviewPause',
        <String, Object>{'textureId': textureId},
      );
    }
    _sourcePreviewPlaying = snapshot.isPlaying;
  }

  Future<void> _applyFallbackIntent(
    EngineIntent intent,
    EngineSnapshot? before,
  ) async {
    final textureId = _sourcePreviewTextureId;
    if (!_androidFallbackEnabled || textureId == null) return;

    Future<void> play() async {
      await _androidPreviewChannel.invokeMethod<void>(
        'sourcePreviewPlay',
        <String, Object>{'textureId': textureId},
      );
      _sourcePreviewPlaying = true;
    }

    Future<void> pause() async {
      await _androidPreviewChannel.invokeMethod<void>(
        'sourcePreviewPause',
        <String, Object>{'textureId': textureId},
      );
      _sourcePreviewPlaying = false;
    }

    Future<void> seekUs(int positionUs) => _androidPreviewChannel.invokeMethod<void>(
          'sourcePreviewSeek',
          <String, Object>{
            'textureId': textureId,
            'positionMs': (positionUs.clamp(0, 1 << 62) / 1000).round(),
          },
        );

    try {
      switch (intent.action) {
        case 'playback.transport.playPause':
          if (before?.isPlaying == true || _sourcePreviewPlaying) {
            await pause();
          } else {
            await play();
          }
          break;
        case 'playback.transport.previousFrame':
          final positionUs = before?.position.inMicroseconds ?? 0;
          await seekUs(positionUs - 33333);
          break;
        case 'playback.transport.nextFrame':
          final positionUs = before?.position.inMicroseconds ?? 0;
          await seekUs(positionUs + 33333);
          break;
        case 'playback.transport.stop':
          await pause();
          await seekUs(0);
          break;
        case 'playback.transport.seek':
          final value = intent.arguments['value'];
          if (value is num) await seekUs(value.toInt());
          break;
      }
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[DigitorEngine] Android source preview transport failed '
          '${error.code}: ${error.message}',
        );
      }
    }
  }

  Future<void> _disposeNativeSourcePreview(int textureId) async {
    try {
      await _androidPreviewChannel.invokeMethod<void>(
        'disposeSourcePreview',
        <String, Object>{'textureId': textureId},
      );
    } on MissingPluginException {
      // The Android plugin has already detached.
    } on PlatformException {
      // Texture teardown is best-effort during engine/app lifecycle changes.
    }
  }

  Future<void> _disposeSourcePreview() async {
    final textureId = _sourcePreviewTextureId;
    _sourcePreviewTextureId = null;
    _sourcePreviewPath = null;
    _sourcePreviewWidth = 0;
    _sourcePreviewHeight = 0;
    _sourcePreviewPlaying = false;
    if (textureId != null) {
      await _disposeNativeSourcePreview(textureId);
    }
  }

  @override
  Future<List<EngineCapability>> discoverCapabilities() async {
    await initialize();
    return _inner.discoverCapabilities();
  }

  @override
  Future<void> dispatch(EngineIntent intent) async {
    await initialize();
    final before = _latestSnapshot;
    await _inner.dispatch(intent);
    await _applyFallbackIntent(intent, before);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final initializing = _initializing;
    if (initializing != null) {
      try {
        await initializing;
      } catch (_) {
        // Initialization failure is already surfaced by the editor. Continue
        // cleanup of the inner gateway.
      }
    }
    await _disposeSourcePreview();
    await _snapshotSubscription?.cancel();
    await _inner.dispose();
    await _snapshotController.close();
  }
}
