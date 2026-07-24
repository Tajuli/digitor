import 'package:digitor/features/editor/domain/models/clip_type.dart';
import 'package:digitor/features/editor/domain/models/clip_adjustments.dart';
import 'package:digitor/features/editor/domain/models/color/color_node_graph.dart';
import 'package:flutter/material.dart';

class TimelineClip {
  TimelineClip({
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
    this.sourceStart = Duration.zero,
    this.sourceDuration,
    this.linkGroupId,
    this.sourceMediaGroupId,
    this.isEmbeddedAudio = false,
    this.colorGroupId,
    this.colorAdjustments = const ClipColorAdjustments(),
    ColorNodeGraph? colorNodeGraph,
    this.filter = ClipFilterType.none,
    this.effect = ClipEffectType.none,
    this.volume = 1,
    this.muted = false,

    this.data = const {},
  }) : colorNodeGraph = colorNodeGraph ?? ColorNodeGraph.defaultGraph(initialGrade: colorAdjustments);

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

  /// Offset into the original media.  It is zero for generated clips.
  final Duration sourceStart;
  final Duration? sourceDuration;

  /// Identifies the two clips created from the same imported video.  This is
  /// deliberately typed data rather than an entry in [data], so linked edit
  /// operations cannot be broken by unrelated clip metadata.
  final String? linkGroupId;
  /// Stable media-origin identity. It is intentionally independent of linking.
  final String? sourceMediaGroupId;
  final bool isEmbeddedAudio;
  final String? colorGroupId;
  final ClipColorAdjustments colorAdjustments;
  final ColorNodeGraph colorNodeGraph;
  final ClipFilterType filter;
  final ClipEffectType effect;
  final double volume;
  final bool muted;

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
    Duration? sourceStart,
    Duration? sourceDuration,
    String? linkGroupId,
    bool clearLinkGroupId = false,
    String? sourceMediaGroupId,
    bool? isEmbeddedAudio,
    String? colorGroupId,
    ClipColorAdjustments? colorAdjustments,
    ColorNodeGraph? colorNodeGraph,
    ClipFilterType? filter,
    ClipEffectType? effect,
    double? volume,
    bool? muted,

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
      sourceStart: sourceStart ?? this.sourceStart,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      linkGroupId: clearLinkGroupId ? null : linkGroupId ?? this.linkGroupId,
      sourceMediaGroupId: sourceMediaGroupId ?? this.sourceMediaGroupId,
      isEmbeddedAudio: isEmbeddedAudio ?? this.isEmbeddedAudio,
      colorGroupId: colorGroupId ?? this.colorGroupId,
      colorAdjustments: colorAdjustments ?? this.colorAdjustments,
      colorNodeGraph: colorNodeGraph ?? this.colorNodeGraph,
      filter: filter ?? this.filter,
      effect: effect ?? this.effect,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      data: data ?? this.data,
    );
  }
}
