import 'package:flutter/material.dart';

import 'timeline_constants.dart';

/// Draws adaptive time divisions. At high zoom it exposes individual frame
/// boundaries, matching frame-accurate desktop editor timelines.
class TimeRuler extends StatelessWidget {
  const TimeRuler({
    super.key,
    required this.duration,
    required this.pixelsPerSecond,
    required this.fps,
  });

  final Duration duration;
  final double pixelsPerSecond;
  final int fps;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: Size(
            (duration.inMicroseconds /
                    Duration.microsecondsPerSecond *
                    pixelsPerSecond)
                .clamp(0, double.infinity)
                .toDouble(),
            TimelineConstants.rulerHeight,
          ),
          painter: _TimeRulerPainter(
            pixelsPerSecond: pixelsPerSecond,
            fps: fps,
          ),
        ),
      );
}

class _TimeRulerPainter extends CustomPainter {
  const _TimeRulerPainter({required this.pixelsPerSecond, required this.fps});

  final double pixelsPerSecond;
  final int fps;

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = Colors.white.withOpacity(.48)
      ..strokeWidth = 1;
    final framePaint = Paint()
      ..color = Colors.lightBlueAccent.withOpacity(.34)
      ..strokeWidth = 1;

    final pixelsPerFrame = fps <= 0 ? 0.0 : pixelsPerSecond / fps;
    if (pixelsPerFrame >= TimelineConstants.minimumPixelsPerFrameForSnap) {
      final frameCount = (size.width / pixelsPerFrame).ceil();
      for (var frame = 0; frame <= frameCount; frame++) {
        final x = frame * pixelsPerFrame;
        final isSecond = frame % fps == 0;
        final isMajorFrame = frame % 5 == 0;
        final height = isSecond ? 18.0 : (isMajorFrame ? 11.0 : 6.0);
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x, size.height - height),
          isSecond ? tickPaint : framePaint,
        );
      }
      return;
    }

    final majorStep = pixelsPerSecond >= 40 ? 1.0 : 5.0;
    final minorStep = majorStep / 5;
    for (var seconds = 0.0;
        seconds * pixelsPerSecond <= size.width;
        seconds += minorStep) {
      final isMajor =
          (seconds / majorStep - (seconds / majorStep).round()).abs() < .001;
      final height = isMajor ? 14.0 : 7.0;
      final x = seconds * pixelsPerSecond;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - height),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TimeRulerPainter oldDelegate) =>
      oldDelegate.pixelsPerSecond != pixelsPerSecond || oldDelegate.fps != fps;
}
