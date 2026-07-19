import 'package:flutter/material.dart';

import '../../domain/models/timeline_track.dart';

class TrackHeader extends StatelessWidget {
  const TrackHeader({
    super.key,
    required this.track,
  });

  final TimelineTrack track;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      color: Colors.grey.shade900,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            track.name,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Icon(Icons.lock_outline, size: 16),
        ],
      ),
    );
  }
}
