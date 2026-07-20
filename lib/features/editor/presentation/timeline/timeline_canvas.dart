import 'dart:async';
import 'package:flutter/material.dart';
import '../../application/project_controller.dart';
import '../../application/timeline_controller.dart';
import '../../application/timeline_math.dart';
import '../../application/playback_controller.dart';
import 'playhead.dart';
import 'time_ruler.dart';
import 'timeline_body.dart';
import 'timeline_constants.dart';
import 'timeline_scroll_controller.dart';

class TimelineCanvas extends StatefulWidget { const TimelineCanvas({super.key, required this.projectController, required this.timelineController, required this.scrollController, required this.playbackController}); final ProjectController projectController; final TimelineController timelineController; final TimelineScrollController scrollController; final PlaybackController playbackController; @override State<TimelineCanvas> createState() => _TimelineCanvasState(); }
class _TimelineCanvasState extends State<TimelineCanvas> {
  Timer? _autoScroll;
  bool _scrubbing = false;
  @override void dispose() { _autoScroll?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) { final project = widget.projectController.project; final width = TimelineMath.durationToPixels(project.duration, widget.timelineController.pixelsPerSecond).clamp(MediaQuery.sizeOf(context).width, double.infinity).toDouble(); final playheadX = TimelineMath.durationToPixels(widget.timelineController.position, widget.timelineController.pixelsPerSecond);
    return Listener(onPointerMove: (event) => _autoScrollAt(event.position.dx), onPointerUp: (_) => _autoScroll?.cancel(), child: SingleChildScrollView(controller: widget.scrollController.horizontal, scrollDirection: Axis.horizontal, child: SizedBox(width: width, child: GestureDetector(behavior: HitTestBehavior.deferToChild, onTapUp: (details) { if (!_scrubbing) _seek(TimelineMath.pixelsToDuration(details.localPosition.dx, widget.timelineController.pixelsPerSecond)); }, child: Stack(children: [Column(children: [TimeRuler(duration: project.duration, pixelsPerSecond: widget.timelineController.pixelsPerSecond), const Divider(height: 1), TimelineBody(tracks: project.tracks, width: width, projectController: widget.projectController, timelineController: widget.timelineController, onMoveEnd: _moveEnd)]), Playhead(x: playheadX, height: TimelineConstants.rulerHeight + 1 + project.tracks.length * TimelineConstants.trackHeight, position: widget.timelineController.position, pixelsPerSecond: widget.timelineController.pixelsPerSecond, onScrubStart: () { _scrubbing = true; widget.playbackController.beginScrub(); }, onScrub: _scrub, onScrubEnd: (value) async { _seek(value); await widget.playbackController.endScrub(widget.timelineController.position); _scrubbing = false; })]))))); }
  void _scrub(Duration value) { widget.timelineController.setPosition(value); widget.playbackController.scrubTo(widget.timelineController.position); }
  void _seek(Duration value) { widget.timelineController.setPosition(value); widget.playbackController.seek(widget.timelineController.position); }
  void _moveEnd(String clipId, String fromTrackId, Duration start, Offset globalPosition) { if (widget.projectController.tracks.isEmpty) return; final box = context.findRenderObject() as RenderBox; final localY = box.globalToLocal(globalPosition).dy - TimelineConstants.rulerHeight - 1; final index = (localY / TimelineConstants.trackHeight).floor().clamp(0, widget.projectController.tracks.length - 1) as int; final target = widget.projectController.tracks[index].id; widget.timelineController.moveClip(clipId: clipId, fromTrackId: fromTrackId, toTrackId: target, start: start); }
  void _autoScrollAt(double globalX) { final box = context.findRenderObject() as RenderBox; final x = box.globalToLocal(Offset(globalX, 0)).dx; final edge = TimelineConstants.autoScrollEdge; final direction = x < edge ? -1.0 : x > box.size.width - edge ? 1.0 : 0.0; _autoScroll?.cancel(); if (direction == 0 || !widget.scrollController.horizontal.hasClients) return; _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) { final controller = widget.scrollController.horizontal; final next = (controller.offset + direction * 8).clamp(0.0, controller.position.maxScrollExtent).toDouble(); controller.jumpTo(next); }); }
}
