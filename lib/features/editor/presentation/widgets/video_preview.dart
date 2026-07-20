import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../application/playback_controller.dart';

class VideoPreview extends StatelessWidget {
  const VideoPreview({
    super.key,
    required this.playbackController,
  });

  final PlaybackController playbackController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: playbackController,
      builder: (context, _) {
        final error = playbackController.error;
        final controller = playbackController.videoController;

        if (error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white70,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          );
        }

        if (controller == null || !controller.value.isInitialized) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final isPlaying = playbackController.isPlaying;
        final ended = playbackController.duration > Duration.zero &&
            playbackController.position >= playbackController.duration;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _togglePlayback(ended),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio > 0
                      ? controller.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(controller),
                ),
              ),
              if (!isPlaying)
                Center(
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _togglePlayback(ended),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: Icon(
                          ended ? Icons.replay_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 46,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: SafeArea(
                  top: false,
                  minimum: EdgeInsets.zero,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.62),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: isPlaying
                                ? 'Pause'
                                : ended
                                    ? 'Replay'
                                    : 'Play',
                            color: Colors.white,
                            onPressed: () => _togglePlayback(ended),
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : ended
                                      ? Icons.replay_rounded
                                      : Icons.play_arrow_rounded,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _sliderValue(),
                              onChangeStart: (_) {
                                playbackController.beginScrub();
                              },
                              onChanged: (value) {
                                playbackController.scrubTo(
                                  _durationFromSlider(value),
                                );
                              },
                              onChangeEnd: (value) {
                                playbackController.endScrub(
                                  _durationFromSlider(value),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_time(playbackController.position)} / '
                            '${_time(playbackController.duration)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _togglePlayback(bool ended) async {
    if (ended) {
      await playbackController.seek(Duration.zero);
    }
    await playbackController.toggle();
  }

  double _sliderValue() {
    final total = playbackController.duration.inMicroseconds;
    if (total <= 0) return 0;

    return (playbackController.position.inMicroseconds / total)
        .clamp(0.0, 1.0);
  }

  Duration _durationFromSlider(double value) {
    final microseconds =
        (playbackController.duration.inMicroseconds * value).round();
    return Duration(microseconds: microseconds);
  }

  String _time(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');

    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
