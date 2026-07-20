import 'package:digitor/features/editor/domain/models/timeline_clip.dart';
import 'package:digitor/features/editor/domain/models/clip_type.dart';

class VideoClip extends TimelineClip {
  const VideoClip({
    required super.id,
    required super.start,
    required super.duration,
    required this.path, super.type = ClipType.video,

    super.position,
    super.scale,
    super.rotation,
    super.opacity,
    super.visible,
    super.locked,
  });

  final String path;
}
