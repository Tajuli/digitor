import 'package:flutter/material.dart';

import '../../domain/models/timeline_track.dart';

class TrackHeader extends StatelessWidget {
  const TrackHeader({
    super.key,
    required this.track,
    this.onAdd,
  });

  final TimelineTrack track;
  final VoidCallback? onAdd;

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
          const SizedBox(height: 4),
          Tooltip(
            message: track.locked ? 'Track is locked' : 'Add to ${track.name}',
            child: IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 22),
              visualDensity: VisualDensity.compact,
              onPressed: track.locked ? null : onAdd,
            ),
          ),
        ],
      ),
    );
  }
}
