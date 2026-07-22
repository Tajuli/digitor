import 'package:digitor/features/editor/domain/models/timeline_clip.dart';
import 'package:digitor/features/editor/domain/models/track_type.dart';

class TimelineTrack {
  const TimelineTrack({
    required this.id,
    required this.name,
    required this.type,
    this.locked = false,
    this.hidden = false,
    this.muted = false,
    this.clips = const [],
  });

  final String id;

  final String name;

  final TrackType type;

  final bool locked;

  final bool hidden;

  final bool muted;

  final List<TimelineClip> clips;

  TimelineTrack copyWith({
    String? id,
    String? name,
    TrackType? type,
    bool? locked,
    bool? hidden,
    bool? muted,
    List<TimelineClip>? clips,
  }) {
    return TimelineTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      locked: locked ?? this.locked,
      hidden: hidden ?? this.hidden,
      muted: muted ?? this.muted,
      clips: clips ?? this.clips,
    );
  }
}
