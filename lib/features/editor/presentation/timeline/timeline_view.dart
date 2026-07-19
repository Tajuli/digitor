import 'package:flutter/material.dart';

import '../../application/project_controller.dart';
import 'time_ruler.dart';
import 'timeline_constants.dart';
import 'track_header.dart';
import 'track_row.dart';

class TimelineView extends StatelessWidget {
  const TimelineView({
    super.key,
    required this.controller,
  });

  final ProjectController controller;

  @override
  Widget build(BuildContext context) {
    final project = controller.project;

    final width = project.duration.inMilliseconds /
        1000 *
        TimelineConstants.pixelsPerSecond;

    return Column(
      children: [
        TimeRuler(
          duration: project.duration,
        ),
        Expanded(
          child: ListView.builder(
            itemCount: project.tracks.length,
            itemBuilder: (_, index) {
              final track = project.tracks[index];

              return Row(
                children: [
                  TrackHeader(track: track),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        child: TrackRow(
                          track: track,
                          timelineWidth: width,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
