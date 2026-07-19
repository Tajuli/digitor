import 'package:digitor/features/editor/domain/models/timeline_clip.dart';

class AudioClip extends TimelineClip {
  const AudioClip({
    required super.id,
    required super.start,
    required super.duration,

    required this.path,

    this.volume = 1,

    super.locked,
    super.visible,
  });

  final String path;

  final double volume;
}
