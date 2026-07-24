import 'package:digitor/features/editor/domain/models/timeline_clip.dart';
import 'package:digitor/features/editor/domain/models/clip_type.dart';

class AudioClip extends TimelineClip {
  AudioClip({
    required super.id,
    required super.start,
    required super.duration,

    required this.path, super.type = ClipType.audio,

    this.volume = 1,

    super.locked,
    super.visible,
  });

  final String path;

  final double volume;
}
