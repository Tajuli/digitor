import 'package:flutter/material.dart';

import '../../application/project_controller.dart';
import '../../domain/models/clip_type.dart';
import '../../domain/models/timeline_clip.dart';
import 'timeline_constants.dart';

class ClipWidget extends StatefulWidget {
  const ClipWidget({super.key, required this.clip, required this.controller, required this.trackId, required this.pixelsPerSecond, required this.onMoveEnd});
  final TimelineClip clip;
  final ProjectController controller;
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
        onHorizontalDragUpdate: (details) => setState(() { _displayStart += Duration(milliseconds: (details.delta.dx / widget.pixelsPerSecond * 1000).round()); if (_displayStart < Duration.zero) _displayStart = Duration.zero; }),
        onHorizontalDragEnd: (details) => widget.onMoveEnd(widget.clip.id, widget.trackId, _displayStart, details.globalPosition),
        child: RepaintBoundary(child: AnimatedContainer(
          duration: TimelineConstants.movementAnimationDuration, width: width, height: TimelineConstants.clipHeight,
          decoration: BoxDecoration(color: _color(widget.clip.type), borderRadius: BorderRadius.circular(TimelineConstants.clipRadius), border: Border.all(color: selected ? Colors.amber : Colors.transparent, width: 2)),
          child: Stack(children: [Center(child: Text(_title(widget.clip.type), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))), if (selected) const _TrimHandle(alignment: Alignment.centerLeft), if (selected) const _TrimHandle(alignment: Alignment.centerRight)]),
        )),
      ),
    );
  }
  Color _color(ClipType type) => switch (type) { ClipType.video => Colors.blue, ClipType.image => Colors.green, ClipType.text => Colors.orange, ClipType.audio => Colors.red, _ => Colors.purple };
  String _title(ClipType type) => type.name.toUpperCase();
}

class _TrimHandle extends StatelessWidget { const _TrimHandle({required this.alignment}); final Alignment alignment; @override Widget build(BuildContext context) => Align(alignment: alignment, child: Container(width: 6, margin: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(.85), borderRadius: BorderRadius.circular(3)))); }
