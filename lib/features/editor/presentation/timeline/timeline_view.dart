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

    final timelineWidth =
        project.duration.inMilliseconds /
        1000 *
        TimelineConstants.pixelsPerSecond;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          children: [
            // Time ruler
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: timelineWidth,
                child: TimeRuler(
                  duration: project.duration,
                ),
              ),
            ),

            const Divider(height: 1),

            // Tracks
            Expanded(
              child: ListView.builder(
                itemCount: project.tracks.length,
                itemBuilder: (context, index) {
                  final track = project.tracks[index];

                  return SizedBox(
                    height: TimelineConstants.trackHeight,
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        TrackHeader(
                          track: track,
                        ),

                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection:
                                Axis.horizontal,
                            child: SizedBox(
                              width: timelineWidth,
                              child: TrackRow(
                                track: track,
                                timelineWidth:
                                    timelineWidth,
                                controller:
                                    controller,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
