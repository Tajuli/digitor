import 'package:flutter/material.dart';

import 'timeline_constants.dart';

/// A grab-friendly transport playhead. Its visual position is controlled by the
/// timeline; only the head consumes drag gestures.
class Playhead extends StatelessWidget {
  const Playhead({super.key, required this.height, required this.onScrubStart, required this.onScrubDelta, required this.onScrubEnd});

  final double height;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubDelta;
  final VoidCallback onScrubEnd;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => onScrubStart(),
        onHorizontalDragUpdate: (details) => onScrubDelta(details.delta.dx),
        onHorizontalDragEnd: (_) => onScrubEnd(),
        onHorizontalDragCancel: onScrubEnd,
        child: SizedBox(
          width: TimelineConstants.playheadHitWidth,
          height: height,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: TimelineConstants.playheadHeadHeight - 2,
                bottom: 0,
                child: Container(width: TimelineConstants.playheadLineWidth, color: Colors.redAccent),
              ),
              const Icon(Icons.arrow_drop_down, size: TimelineConstants.playheadHeadHeight + 10, color: Colors.redAccent),
            ],
          ),
        ),
      );
}
