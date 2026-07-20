import 'package:digitor/features/editor/domain/models/timeline_track.dart';
import 'package:digitor/features/editor/domain/models/track_order.dart';
import 'package:flutter/material.dart';

class EditorProject {
  EditorProject({
    required List<TimelineTrack> tracks,
    required this.duration,

    this.fps = 30,

    this.canvasSize = const Size(1080, 1920),

    this.background = Colors.black,
  }) : tracks = normalizeTrackOrder(tracks);

  final List<TimelineTrack> tracks;

  final Duration duration;

  final int fps;

  final Size canvasSize;

  final Color background;

  EditorProject copyWith({
    List<TimelineTrack>? tracks,
    Duration? duration,
    int? fps,
    Size? canvasSize,
    Color? background,
  }) {
    return EditorProject(
      tracks: tracks ?? this.tracks,
      duration: duration ?? this.duration,
      fps: fps ?? this.fps,
      canvasSize: canvasSize ?? this.canvasSize,
      background: background ?? this.background,
    );
  }
}
