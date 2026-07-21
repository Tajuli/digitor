import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/project_controller.dart';
import '../../application/timeline_controller.dart';
import '../../application/timeline_math.dart';
import '../../domain/models/clip_type.dart';
import '../../domain/models/timeline_clip.dart';
import 'timeline_constants.dart';

class ClipWidget extends StatefulWidget {
  const ClipWidget({super.key, required this.clip, required this.controller, required this.timelineController, required this.trackLocked, required this.trackId, required this.pixelsPerSecond, required this.onMoveEnd, required this.onContextMenu});
  final TimelineClip clip;
  final ProjectController controller;
  final TimelineController timelineController;
  final bool trackLocked;
  final String trackId;
  final double pixelsPerSecond;
  final void Function(String clipId, String trackId, Duration start, Offset globalPosition) onMoveEnd;
  final Future<void> Function(TimelineClip clip, String trackId, Offset position) onContextMenu;
  @override State<ClipWidget> createState() => _ClipWidgetState();
}

class _ClipWidgetState extends State<ClipWidget> {
  late Duration _displayStart;
  Duration? _dragOrigin;
  bool _dragging = false;

  @override void initState() { super.initState(); _displayStart = widget.clip.start; }
  @override void didUpdateWidget(covariant ClipWidget oldWidget) { super.didUpdateWidget(oldWidget); if (!_dragging && oldWidget.clip.start != widget.clip.start) _displayStart = widget.clip.start; }

  bool get _editable => !widget.clip.locked && !widget.trackLocked;

  @override
  Widget build(BuildContext context) {
    final selected = widget.controller.isClipSelected(widget.clip.id);
    final width = (widget.clip.duration.inMilliseconds / 1000 * widget.pixelsPerSecond).clamp(24.0, double.infinity).toDouble();
    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : TimelineConstants.movementAnimationDuration,
      curve: Curves.easeOut,
      left: _displayStart.inMilliseconds / 1000 * widget.pixelsPerSecond,
      top: (TimelineConstants.trackHeight - TimelineConstants.clipHeight) / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.controller.selectClip(trackId: widget.trackId, clipId: widget.clip.id),
        onLongPressStart: !_editable ? null : (_) { _dragOrigin = _displayStart; _dragging = false; },
        onLongPressMoveUpdate: !_editable ? null : (details) {
          final origin = _dragOrigin;
          if (origin == null) return;
          if (!_dragging) { HapticFeedback.selectionClick(); setState(() => _dragging = true); }
          final next = origin + TimelineMath.pixelsToDuration(details.offsetFromOrigin.dx, widget.pixelsPerSecond);
          setState(() => _displayStart = next < Duration.zero ? Duration.zero : next);
        },
        onLongPressEnd: !_editable ? null : (details) async {
          if (_dragging) {
            widget.onMoveEnd(widget.clip.id, widget.trackId, _displayStart, details.globalPosition);
          } else {
            await widget.onContextMenu(widget.clip, widget.trackId, details.globalPosition);
          }
          if (mounted) setState(() { _dragging = false; _dragOrigin = null; });
        },
        child: RepaintBoundary(child: AnimatedContainer(
          duration: _dragging ? Duration.zero : TimelineConstants.movementAnimationDuration,
          width: width, height: TimelineConstants.clipHeight,
          decoration: BoxDecoration(color: _color(widget.clip.type), borderRadius: BorderRadius.circular(TimelineConstants.clipRadius), border: Border.all(color: selected ? Colors.amberAccent : Colors.transparent, width: 2)),
          child: Stack(children: [Center(child: Text(_title(widget.clip.type), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))), if (widget.clip.linkGroupId != null) const Positioned(right: 4, top: 3, child: Icon(Icons.link, color: Colors.white, size: 13)), if (selected && _editable) _TrimHandle(alignment: Alignment.centerLeft, onDelta: _trimLeft), if (selected && _editable) _TrimHandle(alignment: Alignment.centerRight, onDelta: _trimRight)]),
        )),
      ),
    );
  }
  Color _color(ClipType type) => switch (type) { ClipType.video => Colors.blue, ClipType.image => Colors.green, ClipType.text => Colors.orange, ClipType.audio => Colors.red, _ => Colors.purple };
  String _title(ClipType type) => type.name.toUpperCase();
  void _trimLeft(double dx) => widget.timelineController.trimClip(trackId: widget.trackId, clipId: widget.clip.id, start: widget.clip.start + TimelineMath.pixelsToDuration(dx, widget.pixelsPerSecond), end: widget.clip.start + widget.clip.duration, recordHistory: false);
  void _trimRight(double dx) => widget.timelineController.trimClip(trackId: widget.trackId, clipId: widget.clip.id, start: widget.clip.start, end: widget.clip.start + widget.clip.duration + TimelineMath.pixelsToDuration(dx, widget.pixelsPerSecond), recordHistory: false);
}
class _TrimHandle extends StatelessWidget { const _TrimHandle({required this.alignment, required this.onDelta}); final Alignment alignment; final ValueChanged<double> onDelta; @override Widget build(BuildContext context) => Align(alignment: alignment, child: GestureDetector(behavior: HitTestBehavior.opaque, onHorizontalDragUpdate: (d) => onDelta(d.delta.dx), child: Container(width: TimelineConstants.trimHandleWidth, margin: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(.85), borderRadius: BorderRadius.circular(3))))); }
