import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

class PlaybackController extends ChangeNotifier {
  VideoPlayerController? _video;
  bool _disposed = false;
  String? error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;
  Timer? _seekTimer;
  VideoPlayerController? get videoController => _video;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _video?.value.isPlaying ?? false;
  bool get isInitialized => _video?.value.isInitialized ?? false;
  Future<void> replaceMedia(String path) async {
    final old = _video; _video = null; error = null; _position = Duration.zero; _duration = Duration.zero; old?.removeListener(_onVideoChanged); await old?.dispose();
    final next = VideoPlayerController.file(File(path)); _video = next; next.addListener(_onVideoChanged);
    try { await next.initialize(); if (_disposed || _video != next) return; _duration = next.value.duration; notifyListeners(); } catch (_) { if (!_disposed && _video == next) { error = 'Unable to load this video.'; notifyListeners(); } }
  }
  void _onVideoChanged() { final value = _video?.value; if (_disposed || value == null) return; _position = value.position; _duration = value.duration; notifyListeners(); }
  Future<void> play() async { if (isInitialized) await _video!.play(); }
  Future<void> pause() async { if (isInitialized) await _video!.pause(); }
  Future<void> toggle() => isPlaying ? pause() : play();
  Future<void> seek(Duration position) async { if (!isInitialized) return; final target = position < Duration.zero ? Duration.zero : (position > _duration ? _duration : position); await _video!.seekTo(target); }
  Future<void> beginScrub() async { _scrubbing = true; _resumeAfterScrub = isPlaying; if (_resumeAfterScrub) await pause(); }
  void scrubTo(Duration position) { if (!_scrubbing) return; _position = position; notifyListeners(); _seekTimer?.cancel(); _seekTimer = Timer(const Duration(milliseconds: 70), () { seek(position); }); }
  Future<void> endScrub(Duration position) async { _seekTimer?.cancel(); await seek(position); _scrubbing = false; if (_resumeAfterScrub) await play(); }
  @override void dispose() { _disposed = true; _seekTimer?.cancel(); _video?.removeListener(_onVideoChanged); _video?.dispose(); super.dispose(); }
}
