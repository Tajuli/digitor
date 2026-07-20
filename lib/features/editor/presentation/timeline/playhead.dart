import 'package:flutter/material.dart';
import '../../application/timeline_math.dart';
import 'timeline_constants.dart';

class Playhead extends StatelessWidget {
  const Playhead({
    super.key,
    required this.x,
    required this.height,
    required this.position,
    required this.pixelsPerSecond,
    required this.onScrubStart,
    required this.onScrub,
    required this.onScrubEnd,
  });

  final double x;
  final double height;
  final Duration position;
  final double pixelsPerSecond;
  final VoidCallback onScrubStart;
  final ValueChanged<Duration> onScrub;
  final ValueChanged<Duration> onScrubEnd;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x - TimelineConstants.playheadHitWidth / 2,
      top: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => onScrubStart(),
        onHorizontalDragUpdate: (details) => onScrub(TimelineMath.pixelsToDuration(x + details.localPosition.dx - TimelineConstants.playheadHitWidth / 2, pixelsPerSecond)),
        onHorizontalDragEnd: (details) => onScrubEnd(TimelineMath.pixelsToDuration(x + details.localPosition.dx - TimelineConstants.playheadHitWidth / 2, pixelsPerSecond)),
        child: SizedBox(width: TimelineConstants.playheadHitWidth, height: height, child: Column(children: [SizedBox(height: TimelineConstants.playheadLabelHeight, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)), child: Text(_label(position), style: const TextStyle(color: Colors.white, fontSize: 10))),), Container(width: TimelineConstants.playheadHandleSize, height: TimelineConstants.playheadHandleSize, color: Colors.red), Expanded(child: Container(width: TimelineConstants.playheadLineWidth, color: Colors.red))])),
      ),
    );
  }
  String _label(Duration value) => '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}
