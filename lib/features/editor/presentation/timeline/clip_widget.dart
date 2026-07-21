import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../application/audio_waveform_cache.dart';
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
        onTap: _handleTap,
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
          decoration: BoxDecoration(color: _color(widget.clip), borderRadius: BorderRadius.circular(TimelineConstants.clipRadius), border: Border.all(color: selected ? Colors.amberAccent : Colors.transparent, width: 2)),
          child: Stack(children: [
            if (widget.clip.type == ClipType.audio) _AudioWaveform(clip: widget.clip),
            Center(child: Text(_title(widget.clip.type), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
            if (widget.clip.linkGroupId != null) const Positioned(right: 4, top: 3, child: Icon(Icons.link, color: Colors.white, size: 13)),
            if (widget.controller.pendingLinkClipId == widget.clip.id) const Positioned(left: 4, top: 3, child: Icon(Icons.add_link, color: Colors.amberAccent, size: 14)),
            if (selected && _editable) _TrimHandle(alignment: Alignment.centerLeft, onDelta: _trimLeft),
            if (selected && _editable) _TrimHandle(alignment: Alignment.centerRight, onDelta: _trimRight),
          ]),
        )),
      ),
    );
  }

  void _handleTap() {
    final pending = widget.controller.pendingLinkClipId;
    if (pending == null || pending == widget.clip.id) {
      widget.controller.selectClip(trackId: widget.trackId, clipId: widget.clip.id);
      return;
    }

    try {
      widget.timelineController.linkClips(
        firstClipId: pending,
        secondClipId: widget.clip.id,
      );
      widget.controller.selectClip(trackId: widget.trackId, clipId: widget.clip.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clips linked.')),
      );
    } on ArgumentError catch (error) {
      widget.controller.cancelLinkSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message?.toString() ?? 'Unable to link these clips.')),
      );
    }
  }

  Color _color(TimelineClip clip) {
    final group = clip.colorGroupId;
    if (group != null && group != 'standalone-audio') {
      return HSLColor.fromAHSL(1, group.hashCode.abs() % 360, .62, .42).toColor();
    }
    return switch (clip.type) {
      ClipType.video => Colors.blue,
      ClipType.image => Colors.green,
      ClipType.text => Colors.orange,
      ClipType.audio => Colors.deepPurple,
      _ => Colors.purple,
    };
  }
  String _title(ClipType type) => type.name.toUpperCase();
  void _trimLeft(double dx) => widget.timelineController.trimClip(trackId: widget.trackId, clipId: widget.clip.id, start: widget.clip.start + TimelineMath.pixelsToDuration(dx, widget.pixelsPerSecond), end: widget.clip.start + widget.clip.duration, recordHistory: false);
  void _trimRight(double dx) => widget.timelineController.trimClip(trackId: widget.trackId, clipId: widget.clip.id, start: widget.clip.start, end: widget.clip.start + widget.clip.duration + TimelineMath.pixelsToDuration(dx, widget.pixelsPerSecond), recordHistory: false);
}
class _TrimHandle extends StatelessWidget { const _TrimHandle({required this.alignment, required this.onDelta}); final Alignment alignment; final ValueChanged<double> onDelta; @override Widget build(BuildContext context) => Align(alignment: alignment, child: GestureDetector(behavior: HitTestBehavior.opaque, onHorizontalDragUpdate: (d) => onDelta(d.delta.dx), child: Container(width: TimelineConstants.trimHandleWidth, margin: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(.85), borderRadius: BorderRadius.circular(3))))); }


class _AudioWaveform extends StatelessWidget {
  const _AudioWaveform({required this.clip});

  final TimelineClip clip;

  @override
  Widget build(BuildContext context) {
    final path = clip.data['path'] as String?;
    if (path == null || path.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TimelineConstants.clipRadius),
        child: FutureBuilder<List<double>>(
          future: AudioWaveformCache.peaksFor(path),
          builder: (context, snapshot) {
            final peaks = snapshot.data;
            if (peaks == null || peaks.isEmpty) return const SizedBox.shrink();
            return CustomPaint(
              painter: _AudioWaveformPainter(
                peaks: peaks,
                color: Colors.black.withOpacity(.24),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AudioWaveformPainter extends CustomPainter {
  const _AudioWaveformPainter({required this.peaks, required this.color});

  final List<double> peaks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || size.width <= 0 || size.height <= 0) return;
    final paint = Paint()..color = color..strokeWidth = 1;
    final center = size.height / 2;
    final visibleSamples = math.max(1, size.width.floor());
    for (var x = 0; x < visibleSamples; x += 2) {
      final index = (x / visibleSamples * peaks.length).floor().clamp(0, peaks.length - 1).toInt();
      final amplitude = peaks[index] * size.height * .38;
      canvas.drawLine(Offset(x.toDouble(), center - amplitude), Offset(x.toDouble(), center + amplitude), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) => oldDelegate.peaks != peaks || oldDelegate.color != color;
}
