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
