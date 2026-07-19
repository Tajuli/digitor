import 'package:flutter/material.dart';

import 'timeline_constants.dart';

class TimeRuler extends StatelessWidget {
  const TimeRuler({
    super.key,
    required this.duration,
  });

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final seconds = duration.inSeconds + 1;

    return SizedBox(
      height: TimelineConstants.rulerHeight,
      child: Row(
        children: List.generate(seconds, (index) {
          return SizedBox(
            width: TimelineConstants.pixelsPerSecond,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                index.toString(),
                style: const TextStyle(fontSize: 11),
              ),
            ),
          );
        }),
      ),
    );
  }
}
