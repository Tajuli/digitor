import 'package:flutter/material.dart';

import 'timeline_clip.dart';
import '../domain/models/clip_type.dart';

class TextClip extends TimelineClip {
  const TextClip({
    required super.id,
    required super.start,
    required super.duration,

    required this.text, super.type = ClipType.text,

    this.fontSize = 40,
    this.color = Colors.white,

    super.position,
    super.scale,
    super.rotation,
    super.opacity,
    super.visible,
    super.locked,
  });

  final String text;

  final double fontSize;

  final Color color;
}
