import 'package:flutter/material.dart';

import '../../application/project_controller.dart';
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
    required this.controller,
    required this.trackId,
  });

  final TimelineClip clip;
  final ProjectController controller;
  final String trackId;

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
    return "CLIP";
  }

  @override
  Widget build(BuildContext context) {
    final left = clip.start.inMilliseconds /
        1000 *
        TimelineConstants.pixelsPerSecond;

    final width = clip.duration.inMilliseconds /
        1000 *
        TimelineConstants.pixelsPerSecond;

    final selected = controller.isClipSelected(clip.id);

    return Positioned(
      left: left,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          controller.selectClip(
            trackId: trackId,
            clipId: clip.id,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _color(),
            borderRadius: BorderRadius.circular(
              TimelineConstants.clipRadius,
            ),
            border: Border.all(
              color: selected
                  ? Colors.yellow
                  : Colors.transparent,
              width: 3,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.yellow.withOpacity(.35),
                      blurRadius: 10,
                    )
                  ]
                : null,
          ),
          child: Text(
            _title(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
