import 'package:flutter/material.dart';

abstract class TimelineClip {
  const TimelineClip({
    required this.id,
    required this.start,
    required this.duration,
    this.position = Offset.zero,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,
    this.visible = true,
    this.locked = false,
  });

  final String id;

  final Duration start;

  final Duration duration;

  final Offset position;

  final double scale;

  final double rotation;

  final double opacity;

  final bool visible;

  final bool locked;
}
