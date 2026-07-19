import 'dart:io';

import 'thumbnail_generator.dart';

class VideoThumbnailGenerator implements ThumbnailGenerator {
  @override
  Future<List<ThumbnailFrame>> generate({
    required File video,
    required Duration duration,
    Duration interval = const Duration(seconds: 1),
  }) async {
    // TODO:
    // Next milestone:
    // Use the video_thumbnail package
    // Generate thumbnails every [interval]
    // Cache them in the temp directory
    // Return ThumbnailFrame list.

    return const [];
  }
}
