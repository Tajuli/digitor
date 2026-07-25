import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'thumbnail_generator.dart';

class VideoThumbnailGenerator implements ThumbnailGenerator {
  @override
  Future<List<ThumbnailFrame>> generate({
    required File video,
    required Duration duration,
    Duration interval = const Duration(seconds: 1),
  }) async {
    // video_thumbnail currently provides the native extraction path used by
    // Digitor on Android and iOS. Desktop import/playback must still work even
    // when thumbnail extraction is unavailable, so return an empty strip.
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const <ThumbnailFrame>[];
    }

    final List<ThumbnailFrame> frames = [];
    final tempDir = await getTemporaryDirectory();

    for (
      Duration position = Duration.zero;
      position <= duration;
      position += interval
    ) {
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: video.path,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 220,
        quality: 80,
        timeMs: position.inMilliseconds,
      );

      if (thumbnailPath == null) continue;

      frames.add(
        ThumbnailFrame(
          file: File(thumbnailPath),
          position: position,
        ),
      );
    }

    return frames;
  }
}
