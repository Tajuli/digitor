import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';

class MediaMetadata {
  const MediaMetadata({required this.duration, required this.hasVideo, required this.hasAudio, this.width, this.height, this.frameRate});
  final Duration duration;
  final bool hasVideo;
  final bool hasAudio;
  final int? width;
  final int? height;
  final double? frameRate;
}

abstract class MediaMetadataService {
  Future<MediaMetadata?> probeVideo(String path);
  Future<Duration?> probeAudioDuration(String path);
}

/// Small platform-independent probe used by the editor.  `video_player` can
/// reliably validate a playable video and read its duration, but does not
/// expose stream inventory. Android-specific stream probing can replace this
/// service without involving widgets.
class VideoPlayerMediaMetadataService implements MediaMetadataService {
  static const _channel = MethodChannel('digitor/media_metadata');

  @override
  Future<Duration?> probeAudioDuration(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;

    final player = AudioPlayer();
    try {
      final duration = await player.setFilePath(path);
      if (duration == null || duration <= Duration.zero) return null;
      return duration;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }
  @override
  Future<MediaMetadata?> probeVideo(String path) async {
    if (!await File(path).exists()) return null;
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      final value = controller.value;
      if (value.duration <= Duration.zero) return null;
      // Android's MediaExtractor-backed host implementation reports streams.
      // A missing host implementation is handled safely rather than guessing
      // from the filename extension.
      final details = await _probeStreams(path);
      return MediaMetadata(duration: value.duration, hasVideo: details.hasVideo ?? true, hasAudio: details.hasAudio ?? true, width: value.size.width.round(), height: value.size.height.round(), frameRate: details.frameRate);
    } catch (_) {
      return null;
    } finally {
      await controller.dispose();
    }
  }

  Future<_StreamDetails> _probeStreams(String path) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('probe', {'path': path});
      if (result == null) return const _StreamDetails();
      return _StreamDetails(hasVideo: result['hasVideo'] as bool? ?? true, hasAudio: result['hasAudio'] as bool? ?? false, frameRate: (result['frameRate'] as num?)?.toDouble());
    } on PlatformException {
      return const _StreamDetails();
    } on MissingPluginException {
      return const _StreamDetails();
    }
  }
}

class _StreamDetails { const _StreamDetails({this.hasVideo, this.hasAudio, this.frameRate}); final bool? hasVideo; final bool? hasAudio; final double? frameRate; }
