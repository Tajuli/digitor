import 'package:flutter/material.dart';

class TimelineConstants {
  static const double rulerHeight = 32;

  static const double trackHeight = 72;

  static const double headerWidth = 80;

  static const double pixelsPerSecond = 80;

  static const List<double> zoomLevels = [20, 40, 80, 160, 320, 640];
  static const double toolbarHeight = 40;
  static const double clipHeight = 56;
  static const double snapDistance = 10;
  static const double autoScrollEdge = 48;
  static const Duration movementAnimationDuration = Duration(milliseconds: 120);

  static const double clipRadius = 10;

  static const EdgeInsets clipPadding =
      EdgeInsets.symmetric(horizontal: 6);

  static const double playheadWidth = 2;
}
