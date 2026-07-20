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
      final ended = playbackController.duration > Duration.zero && playbackController.position >= playbackController.duration;
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
          Positioned(bottom: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(24)), child: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(tooltip: playbackController.isPlaying ? 'Pause' : (ended ? 'Replay' : 'Play'), iconSize: 30, color: Colors.white, icon: Icon(playbackController.isPlaying ? Icons.pause : (ended ? Icons.replay : Icons.play_arrow)), onPressed: () async { if (ended) await playbackController.seek(Duration.zero); await playbackController.toggle(); }), Text('${_time(playbackController.position)} / ${_time(playbackController.duration)}', style: const TextStyle(color: Colors.white))]))),
        ],
      );
    });
  }

  String _time(Duration value) => '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}
