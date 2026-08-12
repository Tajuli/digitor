import 'dart:async';

import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:flutter/foundation.dart';

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
      : _inner = inner ?? DigitorFfiEngineGateway();

  final DigitorFfiEngineGateway _inner;
  Future<void>? _initializing;
  bool _initialized = false;
  bool _disposed = false;

  @override
  Stream<EngineSnapshot> get snapshots => _inner.snapshots;

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
    await _inner.dispose();
  }
}
