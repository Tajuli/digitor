import 'package:flutter/material.dart';
class TimelineSelectionOverlay extends StatelessWidget { const TimelineSelectionOverlay({super.key, required this.onClear}); final VoidCallback onClear; @override Widget build(BuildContext context) => Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: onClear)); }
