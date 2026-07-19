import 'package:flutter/material.dart';

import '../../application/project_controller.dart';
import '../../domain/models/timeline_track.dart';
import 'clip_widget.dart';
import 'timeline_constants.dart';

class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.timelineWidth,
    required this.controller,
  });

  final TimelineTrack track;
  final double timelineWidth;
  final ProjectController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TimelineConstants.trackHeight,
      child: Stack(
        children: [
          // Track background
          Container(
            width: timelineWidth,
            height: TimelineConstants.trackHeight,
            color: Colors.grey.shade800,
          ),

          // Bottom divider
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.grey.shade700,
            ),
          ),

          // Timeline clips
          ...track.clips.map(
            (clip) => ClipWidget(
              clip: clip,
              controller: controller,
              trackId: track.id,
            ),
          ),
        ],
      ),
    );
  }
}
