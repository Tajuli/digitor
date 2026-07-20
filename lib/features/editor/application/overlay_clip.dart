import 'package:digitor/features/editor/domain/models/timeline_clip.dart';
import 'package:digitor/features/editor/domain/models/clip_type.dart';

class OverlayClip extends TimelineClip {
  const OverlayClip({
    required super.id,
    required super.start,
    required super.duration,
    required this.path, super.type = ClipType.overlay,

    super.position,
    super.scale,
    super.rotation,
    super.opacity,
    super.visible,
    super.locked,
  });

  final String path;
}
