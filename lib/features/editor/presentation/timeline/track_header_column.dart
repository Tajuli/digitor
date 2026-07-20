import 'package:flutter/material.dart';
import '../../domain/models/timeline_track.dart';
import 'timeline_constants.dart';
import 'track_header.dart';
class TrackHeaderColumn extends StatelessWidget {
  const TrackHeaderColumn({super.key, required this.tracks, required this.verticalController, this.onAdd});
  final List<TimelineTrack> tracks;
  final ScrollController verticalController;
  final ValueChanged<TimelineTrack>? onAdd;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const SizedBox(height: TimelineConstants.rulerHeight + 1),
          Expanded(
            child: ListView.builder(
              controller: verticalController,
              itemCount: tracks.length,
              itemExtent: TimelineConstants.trackHeight,
              itemBuilder: (context, index) => TrackHeader(
                track: tracks[index],
                onAdd: onAdd == null ? null : () => onAdd!(tracks[index]),
              ),
            ),
          ),
        ],
      );
}
