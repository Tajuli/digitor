import 'dart:io';

class ThumbnailFrame {
  const ThumbnailFrame({
    required this.file,
    required this.position,
  });

  final File file;
  final Duration position;
}

abstract class ThumbnailGenerator {
  Future<List<ThumbnailFrame>> generate({
    required File video,
    required Duration duration,
    Duration interval = const Duration(seconds: 1),
  });
}
