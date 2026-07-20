import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

class PlaybackController extends ChangeNotifier {
  VideoPlayerController? _video;
  Timer? _seekTimer;
  bool _disposed = false;
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;
  bool _transportPlaying = false;
  String? _sourcePath;
  String? error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  VideoPlayerController? get videoController => _video;
  String? get sourcePath => _sourcePath;
  Duration get position => _position;
  Duration get duration => _duration;

  /// This is the editor transport state, not only the current decoder state.
  /// It stays true while the playhead crosses gaps or switches clips.
  bool get isPlaying => _transportPlaying;
  bool get isInitialized => _video?.value.isInitialized ?? false;

  Future<void> replaceMedia(String path) async {
    if (_sourcePath == path && _video != null) return;

    final old = _video;
    _video = null;
    _sourcePath = path;
    error = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();

    old?.removeListener(_onVideoChanged);
    await old?.dispose();
    if (_disposed || _sourcePath != path) return;

    final next = VideoPlayerController.file(File(path));
    _video = next;
    next.addListener(_onVideoChanged);

    try {
      await next.initialize();
      if (_disposed || _video != next) return;
      _duration = next.value.duration;

      // Timeline audio tracks own audible playback. Keep visual preview silent
      // so linked embedded audio is not played twice.
      await next.setVolume(0);

      if (_transportPlaying) {
        await next.play();
      }
      notifyListeners();
    } catch (_) {
      if (!_disposed && _video == next) {
        error = 'Unable to load this video.';
        notifyListeners();
      }
    }
  }

  Future<void> clearMedia() async {
    if (_video == null && _sourcePath == null) return;
    final old = _video;
    _video = null;
    _sourcePath = null;
    error = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
    old?.removeListener(_onVideoChanged);
    await old?.dispose();
  }

  void _onVideoChanged() {
    final value = _video?.value;
    if (_disposed || value == null) return;
    _position = value.position;
    _duration = value.duration;
    notifyListeners();
  }

  Future<void> play() async {
    if (_transportPlaying) return;
    _transportPlaying = true;
    if (isInitialized) await _video!.play();
    notifyListeners();
  }

  Future<void> pause() async {
    if (!_transportPlaying && !(_video?.value.isPlaying ?? false)) return;
    _transportPlaying = false;
    if (isInitialized) await _video!.pause();
    notifyListeners();
  }

  Future<void> toggle() => isPlaying ? pause() : play();

  Future<void> seek(Duration position) async {
    if (!isInitialized) return;
    final target = position < Duration.zero
        ? Duration.zero
        : position > _duration
            ? _duration
            : position;
    await _video!.seekTo(target);
  }

  Future<void> beginScrub() async {
    _scrubbing = true;
    _resumeAfterScrub = _transportPlaying;
    if (_resumeAfterScrub) await pause();
  }

  void scrubTo(Duration position) {
    if (!_scrubbing) return;
    _position = position;
    notifyListeners();
    _seekTimer?.cancel();
    _seekTimer = Timer(
      const Duration(milliseconds: 70),
      () => seek(position),
    );
  }

  Future<void> endScrub(Duration position) async {
    _seekTimer?.cancel();
    await seek(position);
    _scrubbing = false;
    if (_resumeAfterScrub) await play();
  }

  @override
  void dispose() {
    _disposed = true;
    _seekTimer?.cancel();
    _video?.removeListener(_onVideoChanged);
    _video?.dispose();
    super.dispose();
  }
}
