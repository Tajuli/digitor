import 'package:flutter/widgets.dart';

class TimelineScrollController {
  TimelineScrollController();

  final ScrollController horizontal = ScrollController();

  final ScrollController vertical = ScrollController();
  final ScrollController headerVertical = ScrollController();
  bool _syncingVertical = false;

  void synchronizeVerticalScrollers() {
    vertical.addListener(() => _sync(vertical, headerVertical));
    headerVertical.addListener(() => _sync(headerVertical, vertical));
  }

  void _sync(ScrollController source, ScrollController target) {
    if (_syncingVertical || !source.hasClients || !target.hasClients) return;
    _syncingVertical = true;
    target.jumpTo(source.offset.clamp(0.0, target.position.maxScrollExtent));
    _syncingVertical = false;
  }

  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    headerVertical.dispose();
  }
}
