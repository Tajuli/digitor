import 'dart:async';

import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:flutter/foundation.dart';

import 'engine_gateway.dart';
import 'ffi_engine_gateway.dart';

/// Startup-safe facade for the DigitorEngine-backed application gateway.
///
/// Android Flutter preview is render-target driven. The current qualified
/// SurfaceProducer presenter is OpenGL ES, so AUTO must be resolved before the
/// process-wide DigitorEngine singleton is initialized. Once initialized, the
/// backend remains locked for the lifetime of that engine instance.
final class BootstrappedDigitorEngineGateway implements EngineGateway {
  BootstrappedDigitorEngineGateway({DigitorFfiEngineGateway? inner})
      : _inner = inner ?? DigitorFfiEngineGateway() {
    _snapshotSubscription = _inner.snapshots.listen(
      _snapshotController.add,
      onError: _snapshotController.addError,
    );
  }

  final DigitorFfiEngineGateway _inner;
  final StreamController<EngineSnapshot> _snapshotController =
      StreamController<EngineSnapshot>.broadcast();
  StreamSubscription<EngineSnapshot>? _snapshotSubscription;
  Future<void>? _initializing;
  bool _initialized = false;
  bool _disposed = false;

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
      var preferredBackend = DigitorBackend.automatic;
      DigitorFlutterHostCapabilities? hostCapabilities;

      // Probe the Flutter texture host before initializing the process-wide
      // engine. Android SurfaceProducer currently has a production-qualified
      // GLES presenter, while Vulkan has no qualified presenter yet.
      if (!kIsWeb) {
        final host = DigitorFlutterPlatformHost();
        try {
          hostCapabilities = await host.capabilities();
          if (defaultTargetPlatform == TargetPlatform.android &&
              hostCapabilities.platform == 'android' &&
              hostCapabilities.renderTargetPresentation) {
            preferredBackend = DigitorBackend.openGles;
          }
        } catch (_) {
          // Keep AUTO when platform capability probing is unavailable. Native
          // backend selection/fallback policy remains authoritative.
        } finally {
          await host.close();
        }
      }

      // The native asset must be initialized before production registration.
      // Selecting GLES here is critical: DigitorEngine.initialize() is
      // process-wide and later workspace initialization reuses this instance.
      final engine = DigitorEngine.initialize(
        preferredBackend: preferredBackend,
      );
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

  @override
  Future<List<EngineCapability>> discoverCapabilities() async {
    await initialize();
    return _inner.discoverCapabilities();
  }

  @override
  Future<void> dispatch(EngineIntent intent) async {
    await initialize();
    await _inner.dispatch(intent);
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
    await _snapshotSubscription?.cancel();
    await _inner.dispose();
    await _snapshotController.close();
  }
}
