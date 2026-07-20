import 'dart:io';

import 'package:video_player/video_player.dart';

class MediaMetadata {
  const MediaMetadata({required this.duration, required this.hasVideo, required this.hasAudio, this.width, this.height});
  final Duration duration;
  final bool hasVideo;
  final bool hasAudio;
  final int? width;
  final int? height;
}

abstract class MediaMetadataService {
  Future<MediaMetadata?> probeVideo(String path);
}

/// Small platform-independent probe used by the editor.  `video_player` can
/// reliably validate a playable video and read its duration, but does not
/// expose stream inventory. Android-specific stream probing can replace this
/// service without involving widgets.
class VideoPlayerMediaMetadataService implements MediaMetadataService {
  @override
  Future<MediaMetadata?> probeVideo(String path) async {
    if (!await File(path).exists()) return null;
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      final value = controller.value;
      if (value.duration <= Duration.zero) return null;
      return MediaMetadata(duration: value.duration, hasVideo: true, hasAudio: false, width: value.size.width.round(), height: value.size.height.round());
    } catch (_) {
      return null;
    } finally {
      await controller.dispose();
    }
  }
}
