import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/models/timeline_clip.dart';

/// Plays active timeline audio without decoding the video picture again.
///
/// Video clips commonly contain embedded audio. Using VideoPlayerController for
/// those audio tracks causes Android to decode the original high-resolution
/// video at the same time as the lightweight preview proxy. AudioPlayer reads
/// only the audio stream, substantially reducing decoder and GPU pressure.
class TimelineAudioPlaybackController {
  final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};
  final Set<String> _loading = <String>{};
  bool _disposed = false;

  Future<void> sync({
    required List<TimelineClip> activeClips,
    required Duration timelinePosition,
    required bool shouldPlay,
  }) async {
    if (_disposed) return;

    final activeIds = activeClips.map((clip) => clip.id).toSet();
    final removedIds = _players.keys
        .where((clipId) => !activeIds.contains(clipId))
        .toList(growable: false);

    for (final clipId in removedIds) {
      final player = _players.remove(clipId);
      await player?.stop();
      await player?.dispose();
    }

    for (final clip in activeClips) {
      final path = clip.data['path'] as String?;
      if (path == null || path.isEmpty) continue;

      var player = _players[clip.id];
      if (player == null && !_loading.contains(clip.id)) {
        _loading.add(clip.id);
        final next = AudioPlayer();
        try {
          await next.setFilePath(path, preload: true);
          if (_disposed || !activeIds.contains(clip.id)) {
            await next.dispose();
            continue;
          }
          _players[clip.id] = next;
          player = next;
        } catch (error, stackTrace) {
          debugPrint('Unable to initialize audio clip ${clip.id}: $error');
          debugPrintStack(stackTrace: stackTrace);
          await next.dispose();
        } finally {
          _loading.remove(clip.id);
        }
      }

      if (player == null) continue;

      await player.setVolume(
        clip.muted ? 0 : clip.volume.clamp(0.0, 1.0).toDouble(),
      );

      final sourcePosition = timelinePosition - clip.start + clip.sourceStart;
      final duration = player.duration ?? clip.duration;
      final boundedPosition = sourcePosition < Duration.zero
          ? Duration.zero
          : sourcePosition > duration
              ? duration
              : sourcePosition;
      final drift = (player.position - boundedPosition).abs();

      // During normal playback, let the native audio clock run freely. Seek
      // only after a meaningful drift or while paused/scrubbing.
      if (!shouldPlay || drift > const Duration(milliseconds: 350)) {
        await player.seek(boundedPosition);
      }

      if (shouldPlay && !player.playing) {
        // Do not await playback completion; play() completes when playback ends.
        player.play();
      } else if (!shouldPlay && player.playing) {
        await player.pause();
      }
    }
  }

  Future<void> pauseAll() async {
    for (final player in _players.values) {
      await player.pause();
    }
  }

  void dispose() {
    _disposed = true;
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    _loading.clear();
  }
}
