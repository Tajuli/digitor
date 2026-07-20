import 'package:flutter/material.dart';
import '../../application/project_controller.dart';
import '../../application/timeline_controller.dart';
import '../../domain/models/timeline_track.dart';
import 'track_row.dart';
class TimelineBody extends StatelessWidget { const TimelineBody({super.key, required this.tracks, required this.width, required this.projectController, required this.timelineController, required this.onMoveEnd}); final List<TimelineTrack> tracks; final double width; final ProjectController projectController; final TimelineController timelineController; final void Function(String, String, Duration, Offset) onMoveEnd;
@override Widget build(BuildContext context) => Column(children: tracks.map((track) => RepaintBoundary(child: TrackRow(track: track, timelineWidth: width, controller: projectController, pixelsPerSecond: timelineController.pixelsPerSecond, onMoveEnd: onMoveEnd))).toList()); }
