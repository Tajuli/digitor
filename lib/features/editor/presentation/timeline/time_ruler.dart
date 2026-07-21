import 'package:flutter/material.dart';

import 'timeline_constants.dart';

/// Draws time divisions without competing with clip labels or controls.
class TimeRuler extends StatelessWidget {
  const TimeRuler({super.key, required this.duration, required this.pixelsPerSecond});

  final Duration duration;
  final double pixelsPerSecond;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: Size(
            (duration.inMicroseconds / Duration.microsecondsPerSecond * pixelsPerSecond)
                .clamp(0, double.infinity)
                .toDouble(),
            TimelineConstants.rulerHeight,
          ),
          painter: _TimeRulerPainter(pixelsPerSecond: pixelsPerSecond),
        ),
      );
}

class _TimeRulerPainter extends CustomPainter {
  const _TimeRulerPainter({required this.pixelsPerSecond});

  final double pixelsPerSecond;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(.42)
      ..strokeWidth = 1;
    final majorStep = pixelsPerSecond >= 40 ? 1.0 : 5.0;
    final minorStep = majorStep / 5;
    for (var seconds = 0.0; seconds * pixelsPerSecond <= size.width; seconds += minorStep) {
      final isMajor = (seconds / majorStep - (seconds / majorStep).round()).abs() < .001;
      final height = isMajor ? 14.0 : 7.0;
      final x = seconds * pixelsPerSecond;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - height), paint);
    }
  }

  @override
  bool shouldRepaint(_TimeRulerPainter oldDelegate) =>
      oldDelegate.pixelsPerSecond != pixelsPerSecond;
}
