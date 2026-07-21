import 'package:flutter/material.dart';
import '../../application/project_controller.dart';
import '../../domain/models/timeline_clip.dart';
import '../../domain/models/timeline_track.dart';
import '../../application/timeline_controller.dart';
import 'clip_widget.dart';
import 'timeline_constants.dart';
class TrackRow extends StatelessWidget { const TrackRow({super.key, required this.track, required this.timelineWidth, required this.controller, required this.timelineController, required this.pixelsPerSecond, required this.onMoveEnd, required this.onContextMenu}); final TimelineTrack track; final double timelineWidth; final ProjectController controller; final TimelineController timelineController; final double pixelsPerSecond; final void Function(String, String, Duration, Offset) onMoveEnd; final Future<void> Function(TimelineClip, String, Offset) onContextMenu;
@override Widget build(BuildContext context) => SizedBox(height: TimelineConstants.trackHeight, width: timelineWidth, child: Stack(children: [ColoredBox(color: Colors.grey.shade800), Positioned(left: 0, right: 0, bottom: 0, child: Divider(height: 1, color: Colors.grey.shade700)), ...track.clips.map((clip) => ClipWidget(clip: clip, controller: controller, timelineController: timelineController, trackLocked: track.locked, trackId: track.id, pixelsPerSecond: pixelsPerSecond, onMoveEnd: onMoveEnd, onContextMenu: onContextMenu))])); }
