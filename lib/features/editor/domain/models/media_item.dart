import 'package:flutter/foundation.dart';

@immutable
class MediaItem {
  const MediaItem({
    required this.id,
    required this.path,
    required this.isVideo,
    required this.duration,
    required this.createdAt,
  });

  final String id;
  final String path;
  final bool isVideo;
  final Duration duration;
  final DateTime createdAt;

  MediaItem copyWith({
    String? id,
    String? path,
    bool? isVideo,
    Duration? duration,
    DateTime? createdAt,
  }) {
    return MediaItem(
      id: id ?? this.id,
      path: path ?? this.path,
      isVideo: isVideo ?? this.isVideo,
      duration: duration ?? this.duration,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MediaItem &&
            other.id == id &&
            other.path == path &&
            other.isVideo == isVideo &&
            other.duration == duration &&
            other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(id, path, isVideo, duration, createdAt);

  @override
  String toString() {
    return 'MediaItem('
        'id: $id, '
        'path: $path, '
        'isVideo: $isVideo, '
        'duration: $duration, '
        'createdAt: $createdAt'
        ')';
  }
}
