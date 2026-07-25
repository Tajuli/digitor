import 'package:flutter/material.dart';

class TimelineConstants {
  static const double rulerHeight = 32;

  static const double trackHeight = 68;

  static const double headerWidth = 80;

  static const double pixelsPerSecond = 80;

  static const List<double> zoomLevels = [0.5, 1, 2, 5, 10, 20, 40, 80, 160, 320, 640, 1280, 1920, 3840];
  static const double toolbarHeight = 40;
  static const double clipHeight = 52;
  static const double snapThresholdPixels = 10;
  static const double playheadSnapThresholdPixels = 12;
  static const double minimumPixelsPerFrameForSnap = 8;
  static const double autoScrollEdge = 48;
  static const Duration movementAnimationDuration = Duration(milliseconds: 120);

  static const double clipRadius = 10;

  static const EdgeInsets clipPadding =
      EdgeInsets.symmetric(horizontal: 6);

  static const double playheadWidth = 2;
  static const double playheadLineWidth = 2;
  static const double playheadHandleSize = 12;
  static const double playheadHeadHeight = 22;
  static const double playheadHitWidth = 36;
  static const double playheadLabelHeight = 20;
  static const double trimHandleWidth = 12;
  static const Duration minimumClipDuration = Duration(milliseconds: 200);
  static const double viewportFollowThreshold = .75;
}
