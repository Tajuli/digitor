import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/playback_controller.dart';
import '../../application/project_controller.dart';
import '../../application/timeline_controller.dart';
import '../../application/timeline_math.dart';
import 'playhead.dart';
import 'time_ruler.dart';
import 'timeline_body.dart';
import 'timeline_constants.dart';
import 'timeline_scroll_controller.dart';

class TimelineCanvas extends StatefulWidget {
  const TimelineCanvas({super.key, required this.projectController, required this.timelineController, required this.scrollController, required this.playbackController});
  final ProjectController projectController;
  final TimelineController timelineController;
  final TimelineScrollController scrollController;
  final PlaybackController playbackController;
  @override State<TimelineCanvas> createState() => _TimelineCanvasState();
}

class _TimelineCanvasState extends State<TimelineCanvas> {
  Timer? _autoScroll;
  bool _scrubbing = false;
  @override void dispose() { _autoScroll?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final project = widget.projectController.project;
    return LayoutBuilder(builder: (context, constraints) {
      final width = TimelineMath.durationToPixels(project.duration, widget.timelineController.pixelsPerSecond)
          .clamp(constraints.maxWidth, double.infinity).toDouble();
      final playheadX = TimelineMath.durationToPixels(widget.timelineController.position, widget.timelineController.pixelsPerSecond);
      return Listener(
        onPointerMove: (event) => _autoScrollAt(event.position),
        onPointerUp: (_) => _autoScroll?.cancel(),
        child: SingleChildScrollView(
          controller: widget.scrollController.horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Stack(children: [
              Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTapUp: (details) { if (!_scrubbing) { widget.projectController.clearSelection(); _seek(TimelineMath.pixelsToDuration(details.localPosition.dx, widget.timelineController.pixelsPerSecond)); } })),
              Column(children: [
                TimeRuler(duration: project.duration, pixelsPerSecond: widget.timelineController.pixelsPerSecond),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: widget.scrollController.vertical,
                    child: TimelineBody(tracks: project.tracks, width: width, projectController: widget.projectController, timelineController: widget.timelineController, onMoveEnd: _moveEnd),
                  ),
                ),
              ]),
              Positioned(
                left: playheadX - TimelineConstants.playheadHitWidth / 2,
                top: 0,
                child: Playhead(x: TimelineConstants.playheadHitWidth / 2, height: constraints.maxHeight, position: widget.timelineController.position, pixelsPerSecond: widget.timelineController.pixelsPerSecond, onScrubStart: () { _scrubbing = true; widget.playbackController.beginScrub(); }, onScrub: _scrub, onScrubEnd: (value) async { _seek(value); await widget.playbackController.endScrub(widget.timelineController.position); _scrubbing = false; }),
              ),
            ]),
          ),
        ),
      );
    });
  }
  void _scrub(Duration value) { widget.timelineController.setPosition(value); widget.playbackController.scrubTo(widget.timelineController.position); }
  void _seek(Duration value) { widget.timelineController.setPosition(value); }
  void _moveEnd(String clipId, String fromTrackId, Duration start, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final y = box.globalToLocal(globalPosition).dy - TimelineConstants.rulerHeight - 1 + widget.scrollController.vertical.offset;
    if (widget.projectController.tracks.isEmpty) return;
    final index = (y / TimelineConstants.trackHeight)
        .floor()
        .clamp(0, widget.projectController.tracks.length - 1) as int;
    widget.timelineController.moveClip(clipId: clipId, fromTrackId: fromTrackId, toTrackId: widget.projectController.tracks[index].id, start: start);
  }
  void _autoScrollAt(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    final edge = TimelineConstants.autoScrollEdge;
    final horizontal = local.dx < edge ? -1.0 : local.dx > box.size.width - edge ? 1.0 : 0.0;
    final vertical = local.dy < edge ? -1.0 : local.dy > box.size.height - edge ? 1.0 : 0.0;
    _autoScroll?.cancel();
    if (horizontal == 0 && vertical == 0) return;
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _scrollBy(widget.scrollController.horizontal, horizontal * 8);
      _scrollBy(widget.scrollController.vertical, vertical * 6);
    });
  }
  void _scrollBy(ScrollController controller, double amount) { if (controller.hasClients && amount != 0) controller.jumpTo((controller.offset + amount).clamp(0.0, controller.position.maxScrollExtent)); }
}
