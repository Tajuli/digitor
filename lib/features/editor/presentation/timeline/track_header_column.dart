import 'package:flutter/material.dart';
import '../../domain/models/timeline_track.dart';
import 'timeline_constants.dart';
import 'track_header.dart';
class TrackHeaderColumn extends StatelessWidget { const TrackHeaderColumn({super.key, required this.tracks}); final List<TimelineTrack> tracks; @override Widget build(BuildContext context) => Column(children: [const SizedBox(height: TimelineConstants.rulerHeight + 1), ...tracks.map((track) => SizedBox(height: TimelineConstants.trackHeight, child: TrackHeader(track: track)))]); }
