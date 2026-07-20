import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../domain/models/timeline_clip.dart';

/// Plays every active timeline audio clip concurrently.
///
/// Each active clip owns a lightweight media controller. The visual preview is
/// muted separately, so linked video audio is heard only through its audio
/// track and is not doubled.
class TimelineAudioPlaybackController {
  final Map<String, VideoPlayerController> _players = {};
  final Set<String> _loading = {};
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
      await player?.pause();
      await player?.dispose();
    }

    for (final clip in activeClips) {
      final path = clip.data['path'] as String?;
      if (path == null || path.isEmpty) continue;

      var player = _players[clip.id];
      if (player == null && !_loading.contains(clip.id)) {
        _loading.add(clip.id);
        final next = VideoPlayerController.file(File(path));
        try {
          await next.initialize();
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

      if (player == null || !player.value.isInitialized) continue;

      await player.setVolume(clip.muted ? 0 : clip.volume.clamp(0.0, 1.0).toDouble());
      final sourcePosition = timelinePosition - clip.start + clip.sourceStart;
      final boundedPosition = sourcePosition < Duration.zero
          ? Duration.zero
          : sourcePosition > player.value.duration
              ? player.value.duration
              : sourcePosition;
      final drift = (player.value.position - boundedPosition).abs();
      if (!shouldPlay || drift > const Duration(milliseconds: 250)) {
        await player.seekTo(boundedPosition);
      }
      if (shouldPlay && !player.value.isPlaying) {
        await player.play();
      } else if (!shouldPlay && player.value.isPlaying) {
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
