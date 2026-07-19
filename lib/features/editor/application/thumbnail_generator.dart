import 'dart:io';

/// Represents a generated thumbnail.
class ThumbnailFrame {
  const ThumbnailFrame({
    required this.file,
    required this.position,
  });

  /// Generated thumbnail image.
  final File file;

  /// Position in the source video.
  final Duration position;
}

/// Base contract for thumbnail generation.
///
/// Later this can be replaced by FFmpeg or video_thumbnail
/// without changing the UI.
abstract class ThumbnailGenerator {
  Future<List<ThumbnailFrame>> generate({
    required File video,
    required Duration duration,
    Duration interval = const Duration(seconds: 1),
  });
}
