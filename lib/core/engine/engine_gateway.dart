import 'dart:async';

import 'package:flutter/services.dart';

/// The only Dart-side boundary to DigitorEngine.
///
/// Dart forwards user intent and renders read-only engine state. It must never
/// decode media, mutate the authoritative timeline, render frames, process
/// audio/effects, or encode/export media.
abstract interface class EngineGateway {
  Stream<EngineSnapshot> get snapshots;
  Stream<EngineProgress> get progress;
  Stream<EngineEvent> get events;

  Future<void> initialize();
  Future<List<EngineCapability>> discoverCapabilities();
  Future<void> dispatch(EngineIntent intent);
  Future<void> dispose();
}

final class EngineIntent {
  const EngineIntent(this.action, [this.arguments = const <String, Object?>{}]);

  final String action;
  final Map<String, Object?> arguments;
}

final class EngineCapability {
  const EngineCapability({
    required this.id,
    required this.category,
    required this.title,
    required this.supported,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String category;
  final String title;
  final bool supported;
  final Map<String, Object?> metadata;

  factory EngineCapability.fromMap(Map<Object?, Object?> map) {
    return EngineCapability(
      id: map['id']?.toString() ?? 'unknown',
      category: map['category']?.toString() ?? 'Engine',
      title: map['title']?.toString() ?? map['id']?.toString() ?? 'Unknown',
      supported: map['supported'] != false,
      metadata: Map<String, Object?>.from(
        (map['metadata'] as Map<Object?, Object?>?) ?? const <Object?, Object?>{},
      ),
    );
  }
}

final class EngineSnapshot {
  const EngineSnapshot({
    required this.connected,
    required this.projectOpen,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.state,
    this.engineMessage,
  });

  final bool connected;
  final bool projectOpen;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Map<String, Object?> state;
  final String? engineMessage;

  factory EngineSnapshot.fromMap(Map<Object?, Object?> map) {
    int micros(Object? value) => value is num ? value.toInt() : 0;
    return EngineSnapshot(
      connected: map['connected'] != false,
      projectOpen: map['projectOpen'] == true,
      isPlaying: map['isPlaying'] == true,
      position: Duration(microseconds: micros(map['positionUs'])),
      duration: Duration(microseconds: micros(map['durationUs'])),
      state: Map<String, Object?>.from(
        (map['state'] as Map<Object?, Object?>?) ?? const <Object?, Object?>{},
      ),
      engineMessage: map['message']?.toString(),
    );
  }

  static const disconnected = EngineSnapshot(
    connected: false,
    projectOpen: false,
    isPlaying: false,
    position: Duration.zero,
    duration: Duration.zero,
    state: <String, Object?>{},
    engineMessage: 'Native DigitorEngine host is not connected.',
  );
}

final class EngineProgress {
  const EngineProgress({required this.operation, required this.fraction});

  final String operation;
  final double fraction;

  factory EngineProgress.fromMap(Map<Object?, Object?> map) => EngineProgress(
        operation: map['operation']?.toString() ?? 'engine',
        fraction: ((map['fraction'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      );
}

final class EngineEvent {
  const EngineEvent(this.type, this.payload);

  final String type;
  final Map<String, Object?> payload;

  factory EngineEvent.fromMap(Map<Object?, Object?> map) => EngineEvent(
        map['type']?.toString() ?? 'event',
        Map<String, Object?>.from(
          (map['payload'] as Map<Object?, Object?>?) ?? const <Object?, Object?>{},
        ),
      );
}

/// Native-host protocol used by Windows/Android/macOS/iOS adapters.
///
/// The host implementation is responsible for binding this protocol to the
/// verified DigitorEngine C/C++ API and native Flutter texture presenter.
final class MethodChannelEngineGateway implements EngineGateway {
  MethodChannelEngineGateway({
    MethodChannel? methodChannel,
    EventChannel? snapshotChannel,
    EventChannel? progressChannel,
    EventChannel? eventChannel,
  })  : _methods = methodChannel ?? const MethodChannel('digitor.engine/methods.v1'),
        _snapshotEvents = snapshotChannel ?? const EventChannel('digitor.engine/snapshots.v1'),
        _progressEvents = progressChannel ?? const EventChannel('digitor.engine/progress.v1'),
        _engineEvents = eventChannel ?? const EventChannel('digitor.engine/events.v1');

  final MethodChannel _methods;
  final EventChannel _snapshotEvents;
  final EventChannel _progressEvents;
  final EventChannel _engineEvents;

  Stream<EngineSnapshot>? _snapshots;
  Stream<EngineProgress>? _progress;
  Stream<EngineEvent>? _events;

  @override
  Stream<EngineSnapshot> get snapshots => _snapshots ??= _snapshotEvents
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => EngineSnapshot.fromMap(event as Map<Object?, Object?>));

  @override
  Stream<EngineProgress> get progress => _progress ??= _progressEvents
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => EngineProgress.fromMap(event as Map<Object?, Object?>));

  @override
  Stream<EngineEvent> get events => _events ??= _engineEvents
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => EngineEvent.fromMap(event as Map<Object?, Object?>));

  @override
  Future<void> initialize() => _methods.invokeMethod<void>('initialize');

  @override
  Future<List<EngineCapability>> discoverCapabilities() async {
    final raw = await _methods.invokeListMethod<Object?>('discoverCapabilities');
    return (raw ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(EngineCapability.fromMap)
        .toList(growable: false);
  }

  @override
  Future<void> dispatch(EngineIntent intent) => _methods.invokeMethod<void>(
        'dispatch',
        <String, Object?>{'action': intent.action, 'arguments': intent.arguments},
      );

  @override
  Future<void> dispose() async {
    try {
      await _methods.invokeMethod<void>('dispose');
    } on PlatformException {
      // Native lifecycle already ended.
    } on MissingPluginException {
      // No platform host was registered.
    }
  }
}
