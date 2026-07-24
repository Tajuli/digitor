import 'package:digitor/features/editor/domain/models/media_item.dart';
import 'package:flutter/foundation.dart';

@immutable
class EditorSession {
  EditorSession({
    required this.media,
    required this.trimStart,
    required this.trimEnd,
    required this.rotation,
    required this.scale,
    required this.opacity,
    required this.muted,
    required List<String> appliedFilters,
  }) : appliedFilters = List.unmodifiable(appliedFilters);

  factory EditorSession.initial(MediaItem media) {
    return EditorSession(
      media: media,
      trimStart: Duration.zero,
      trimEnd: media.duration,
      rotation: 0,
      scale: 1,
      opacity: 1,
      muted: false,
      appliedFilters: const [],
    );
  }

  final MediaItem media;
  final Duration trimStart;
  final Duration trimEnd;
  final double rotation;
  final double scale;
  final double opacity;
  final bool muted;
  final List<String> appliedFilters;

  EditorSession copyWith({
    MediaItem? media,
    Duration? trimStart,
    Duration? trimEnd,
    double? rotation,
    double? scale,
    double? opacity,
    bool? muted,
    List<String>? appliedFilters,
  }) {
    return EditorSession(
      media: media ?? this.media,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
      muted: muted ?? this.muted,
      appliedFilters: appliedFilters ?? this.appliedFilters,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is EditorSession &&
            other.media == media &&
            other.trimStart == trimStart &&
            other.trimEnd == trimEnd &&
            other.rotation == rotation &&
            other.scale == scale &&
            other.opacity == opacity &&
            other.muted == muted &&
            listEquals(other.appliedFilters, appliedFilters);
  }

  @override
  int get hashCode => Object.hash(
    media,
    trimStart,
    trimEnd,
    rotation,
    scale,
    opacity,
    muted,
    Object.hashAll(appliedFilters),
  );

  @override
  String toString() {
    return 'EditorSession('
        'media: $media, '
        'trimStart: $trimStart, '
        'trimEnd: $trimEnd, '
        'rotation: $rotation, '
        'scale: $scale, '
        'opacity: $opacity, '
        'muted: $muted, '
        'appliedFilters: $appliedFilters'
        ')';
  }
}
