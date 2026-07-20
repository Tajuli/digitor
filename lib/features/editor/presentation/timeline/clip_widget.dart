import 'package:flutter/material.dart';

import '../../application/project_controller.dart';
import '../../application/timeline_controller.dart';
import '../../application/timeline_math.dart';
import '../../domain/models/clip_type.dart';
import '../../domain/models/timeline_clip.dart';
import 'timeline_constants.dart';

class ClipWidget extends StatefulWidget {
  const ClipWidget({super.key, required this.clip, required this.controller, required this.timelineController, required this.trackLocked, required this.trackId, required this.pixelsPerSecond, required this.onMoveEnd});
  final TimelineClip clip;
  final ProjectController controller;
  final TimelineController timelineController;
  final bool trackLocked;
  final String trackId;
  final double pixelsPerSecond;
  final void Function(String clipId, String trackId, Duration start, Offset globalPosition) onMoveEnd;
  @override State<ClipWidget> createState() => _ClipWidgetState();
}

class _ClipWidgetState extends State<ClipWidget> {
  late Duration _displayStart;
  @override void initState() { super.initState(); _displayStart = widget.clip.start; }
  @override void didUpdateWidget(covariant ClipWidget oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.clip.start != widget.clip.start) _displayStart = widget.clip.start; }
  @override Widget build(BuildContext context) {
    final selected = widget.controller.isClipSelected(widget.clip.id);
    final width = (widget.clip.duration.inMilliseconds / 1000 * widget.pixelsPerSecond).clamp(24.0, double.infinity).toDouble();
    return AnimatedPositioned(
      duration: TimelineConstants.movementAnimationDuration,
      curve: Curves.easeOut,
      left: _displayStart.inMilliseconds / 1000 * widget.pixelsPerSecond,
      top: (TimelineConstants.trackHeight - TimelineConstants.clipHeight) / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.controller.selectClip(trackId: widget.trackId, clipId: widget.clip.id),
        onHorizontalDragUpdate: widget.clip.locked || widget.trackLocked ? null : (details) => setState(() { _displayStart += TimelineMath.pixelsToDuration(details.delta.dx, widget.pixelsPerSecond); if (_displayStart < Duration.zero) _displayStart = Duration.zero; }),
        onHorizontalDragEnd: widget.clip.locked || widget.trackLocked ? null : (details) => widget.onMoveEnd(widget.clip.id, widget.trackId, _displayStart, details.globalPosition),
        child: RepaintBoundary(child: AnimatedContainer(
          duration: TimelineConstants.movementAnimationDuration, width: width, height: TimelineConstants.clipHeight,
          decoration: BoxDecoration(color: _color(widget.clip.type), borderRadius: BorderRadius.circular(TimelineConstants.clipRadius), border: Border.all(color: selected ? Colors.amber : Colors.transparent, width: 2)),
          child: Stack(children: [Center(child: Text(_title(widget.clip.type), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))), if (selected && !widget.clip.locked && !widget.trackLocked) _TrimHandle(alignment: Alignment.centerLeft, onDelta: (dx) => _trimLeft(dx)), if (selected && !widget.clip.locked && !widget.trackLocked) _TrimHandle(alignment: Alignment.centerRight, onDelta: (dx) => _trimRight(dx))]),
        )),
      ),
    );
  }
  Color _color(ClipType type) => switch (type) { ClipType.video => Colors.blue, ClipType.image => Colors.green, ClipType.text => Colors.orange, ClipType.audio => Colors.red, _ => Colors.purple };
  String _title(ClipType type) => type.name.toUpperCase();
  void _trimLeft(double dx) { final delta = TimelineMath.pixelsToDuration(dx, widget.pixelsPerSecond); widget.timelineController.trimClip(trackId: widget.trackId, clipId: widget.clip.id, start: widget.clip.start + delta, end: widget.clip.start + widget.clip.duration, recordHistory: false); }
  void _trimRight(double dx) { final delta = TimelineMath.pixelsToDuration(dx, widget.pixelsPerSecond); widget.timelineController.trimClip(trackId: widget.trackId, clipId: widget.clip.id, start: widget.clip.start, end: widget.clip.start + widget.clip.duration + delta, recordHistory: false); }
}

class _TrimHandle extends StatelessWidget { const _TrimHandle({required this.alignment, required this.onDelta}); final Alignment alignment; final ValueChanged<double> onDelta; @override Widget build(BuildContext context) => Align(alignment: alignment, child: GestureDetector(behavior: HitTestBehavior.opaque, onHorizontalDragUpdate: (d) => onDelta(d.delta.dx), child: Container(width: TimelineConstants.trimHandleWidth, margin: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(.85), borderRadius: BorderRadius.circular(3))))); }
