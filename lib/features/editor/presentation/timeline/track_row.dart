import 'package:flutter/material.dart';

import '../../domain/models/timeline_track.dart';
import 'clip_widget.dart';
import 'timeline_constants.dart';

class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.timelineWidth,
  });

  final TimelineTrack track;

  final double timelineWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TimelineConstants.trackHeight,
      child: Stack(
        children: [
          Container(
            width: timelineWidth,
            color: Colors.grey.shade800,
          ),
          ...track.clips.map(
            (clip) => ClipWidget(
              clip: clip,
            ),
          ),
        ],
      ),
    );
  }
}
