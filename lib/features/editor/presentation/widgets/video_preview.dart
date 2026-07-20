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
    return AnimatedBuilder(animation: playbackController, builder: (context, _) {
      if (playbackController.error != null) return Center(child: Text(playbackController.error!));
      final controller = playbackController.videoController;
      if (controller == null || !controller.value.isInitialized) return const Center(child: CircularProgressIndicator());
      return Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              iconSize: 56,
              color: Colors.white,
              icon: Icon(
                playbackController.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              onPressed: playbackController.toggle,
            ),
          ),
        ],
      );
    });
  }
}
