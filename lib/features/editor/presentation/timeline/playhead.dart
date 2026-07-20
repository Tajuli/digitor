import 'package:flutter/material.dart';

import 'timeline_constants.dart';

class Playhead extends StatelessWidget {
  const Playhead({
    super.key,
    required this.height,
    required this.position,
    required this.onScrubStart,
    required this.onScrubDelta,
    required this.onScrubEnd,
  });

  final double height;
  final Duration position;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubDelta;
  final VoidCallback onScrubEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => onScrubStart(),
      onHorizontalDragUpdate: (details) => onScrubDelta(details.delta.dx),
      onHorizontalDragEnd: (_) => onScrubEnd(),
      onHorizontalDragCancel: onScrubEnd,
      child: SizedBox(
        width: TimelineConstants.playheadHitWidth,
        height: height,
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 42),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _label(position),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              width: TimelineConstants.playheadHandleSize,
              height: TimelineConstants.playheadHandleSize,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Container(
                width: TimelineConstants.playheadLineWidth,
                color: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
