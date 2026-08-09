/// Presentation-facing contract to DigitorEngine.
///
/// Implementations may marshal data to/from the verified native ABI, but must
/// never implement media processing, authoritative timeline logic, rendering,
/// effects, audio processing, encoding, or export behavior in Dart.
abstract interface class EngineGateway {
  Stream<EngineSnapshot> get snapshots;
  Stream<EngineProgress> get progress;

  Future<void> initialize();
  Future<void> dispatch(EngineIntent intent);
  Future<void> dispose();
}

/// A user intent forwarded to DigitorEngine.
sealed class EngineIntent {
  const EngineIntent();
}

final class ImportMediaIntent extends EngineIntent {
  const ImportMediaIntent(this.uris);

  final List<Uri> uris;
}

final class ExportIntent extends EngineIntent {
  const ExportIntent(this.destination);

  final Uri destination;
}

/// UI-facing, read-only view of authoritative engine state.
final class EngineSnapshot {
  const EngineSnapshot({
    required this.projectOpen,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.engineMessage,
  });

  final bool projectOpen;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final String? engineMessage;
}

final class EngineProgress {
  const EngineProgress({
    required this.operation,
    required this.fraction,
  });

  final String operation;
  final double fraction;
}
