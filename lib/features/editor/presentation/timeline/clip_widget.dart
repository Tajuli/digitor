import 'package:flutter/material.dart';

import '../../domain/models/audio_clip.dart';
import '../../domain/models/image_clip.dart';
import '../../domain/models/overlay_clip.dart';
import '../../domain/models/text_clip.dart';
import '../../domain/models/timeline_clip.dart';
import '../../domain/models/video_clip.dart';
import 'timeline_constants.dart';

class ClipWidget extends StatelessWidget {
  const ClipWidget({
    super.key,
    required this.clip,
  });

  final TimelineClip clip;

  Color _color() {
    if (clip is VideoClip) return Colors.blue;
    if (clip is ImageClip) return Colors.green;
    if (clip is TextClip) return Colors.orange;
    if (clip is OverlayClip) return Colors.purple;
    if (clip is AudioClip) return Colors.red;
    return Colors.grey;
  }

  String _title() {
    if (clip is VideoClip) return "VIDEO";
    if (clip is ImageClip) return "IMAGE";
    if (clip is TextClip) return "TEXT";
    if (clip is OverlayClip) return "OVERLAY";
    if (clip is AudioClip) return "AUDIO";
    return "";
  }

  @override
  Widget build(BuildContext context) {
    final left = clip.start.inMilliseconds /
        1000 *
        TimelineConstants.pixelsPerSecond;

    final width = clip.duration.inMilliseconds /
        1000 *
        TimelineConstants.pixelsPerSecond;

    return Positioned(
      left: left,
      child: Container(
        width: width,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _color(),
          borderRadius:
              BorderRadius.circular(TimelineConstants.clipRadius),
        ),
        child: Text(
          _title(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
