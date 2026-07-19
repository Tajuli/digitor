import 'package:digitor/features/editor/domain/models/clip_type.dart';
import 'package:flutter/material.dart';

class TimelineClip {
  const TimelineClip({
    required this.id,
    required this.type,
    required this.start,
    required this.duration,

    this.position = Offset.zero,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,

    this.visible = true,
    this.locked = false,

    this.data = const {},
  });

  final String id;

  final ClipType type;

  final Duration start;

  final Duration duration;

  final Offset position;

  final double scale;

  final double rotation;

  final double opacity;

  final bool visible;

  final bool locked;

  final Map<String, dynamic> data;

  TimelineClip copyWith({
    String? id,
    ClipType? type,
    Duration? start,
    Duration? duration,

    Offset? position,
    double? scale,
    double? rotation,
    double? opacity,

    bool? visible,
    bool? locked,

    Map<String, dynamic>? data,
  }) {
    return TimelineClip(
      id: id ?? this.id,
      type: type ?? this.type,
      start: start ?? this.start,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      data: data ?? this.data,
    );
  }
}
