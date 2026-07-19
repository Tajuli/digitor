import 'package:flutter/widgets.dart';

class TimelineScrollController {
  TimelineScrollController();

  final ScrollController horizontal = ScrollController();

  final ScrollController vertical = ScrollController();

  void dispose() {
    horizontal.dispose();
    vertical.dispose();
  }
}
