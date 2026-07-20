import 'package:flutter/foundation.dart';

import 'project_controller.dart';
import '../domain/models/timeline_clip.dart';
import '../domain/models/timeline_track.dart';
import '../domain/models/track_type.dart';
import '../domain/models/clip_type.dart';
import '../domain/models/editor_project.dart';
import 'editor_history_controller.dart';
import 'project_commands.dart';
import 'timeline_math.dart';

class TimelineController extends ChangeNotifier {
  TimelineController({
    required this.projectController,
    this.pixelsPerSecond = 80,
    this.snapDistance = 10,
  }) : history = EditorHistoryController();

  final ProjectController projectController;

  double pixelsPerSecond;
  final double snapDistance;
  final EditorHistoryController history;

  Duration _position = Duration.zero;
  Duration _trimStart = Duration.zero;
  Duration _trimEnd = const Duration(minutes: 1);

  Duration get position => _position;
  Duration get trimStart => _trimStart;
  Duration get trimEnd => _trimEnd;

  double get zoom => pixelsPerSecond;

  /// The supported zoom presets are intentionally discrete so timeline layout
  /// remains predictable for thumbnails and future waveform rendering.
  void setZoom(double pixels) {
    if (pixelsPerSecond == pixels) return;
    pixelsPerSecond = pixels;
    notifyListeners();
  }

  void setPosition(Duration value, {bool notify = true}) {
    value = TimelineMath.clampTimelinePosition(value, projectController.project.duration);
    if (value == _position) return;
    _position = value;
    if (notify) notifyListeners();
  }

  void setTrimStart(Duration value) {
    if (value == _trimStart) return;

    _trimStart = value;

    if (_trimStart > _trimEnd) {
      _trimStart = _trimEnd;
    }

    notifyListeners();
  }

  void setTrimEnd(Duration value) {
    if (value == _trimEnd) return;

    _trimEnd = value;

    if (_trimEnd < _trimStart) {
      _trimEnd = _trimStart;
    }

    notifyListeners();
  }

  void zoomIn() {
    final index = _nearestZoomIndex();
    setZoom(TimelineZoom.levels[index < TimelineZoom.levels.length - 1 ? index + 1 : index]);
  }

  void zoomOut() {
    final index = _nearestZoomIndex();
    setZoom(TimelineZoom.levels[index > 0 ? index - 1 : index]);
  }

  int _nearestZoomIndex() => TimelineZoom.levels.indexOf(
        TimelineZoom.levels.reduce((a, b) =>
            (a - pixelsPerSecond).abs() < (b - pixelsPerSecond).abs() ? a : b),
      );

  /// Moves a clip, optionally to another compatible track, after magnetic snap.
  void moveClip({required String clipId, required String fromTrackId, required String toTrackId, required Duration start, bool recordHistory = true}) {
    final source = _track(fromTrackId);
    final destination = _track(toTrackId);
    if (source == null || destination == null || source.locked || destination.locked || !_accepts(destination, _clip(source, clipId))) return;
    final clip = _clip(source, clipId)!;
    if (clip.locked) return;
    final moved = clip.copyWith(start: snap(start, excludingClipId: clipId));
    final tracks = projectController.tracks.map((track) {
      if (track.id == fromTrackId && track.id == toTrackId) return track.copyWith(clips: track.clips.map((item) => item.id == clipId ? moved : item).toList());
      if (track.id == fromTrackId) return track.copyWith(clips: track.clips.where((item) => item.id != clipId).toList());
      if (track.id == toTrackId) return track.copyWith(clips: [...track.clips, moved]);
      return track;
    }).toList();
    _apply(projectController.project.copyWith(tracks: tracks), recordHistory ? MoveClipCommand(projectController, projectController.project, projectController.project.copyWith(tracks: tracks)) : null);
  }

  /// Splits a clip at [position], preserving the original clip's metadata.
  void splitClip({required String trackId, required String clipId, required Duration position}) {
    final track = _track(trackId);
    if (track == null) return;

    final clip = _clip(track, clipId);
    if (clip == null) return;
    if (track.locked || clip.locked) return;
    if (position <= clip.start || position >= clip.start + clip.duration) return;

    final firstDuration = position - clip.start;
    final second = clip.copyWith(
      id: _splitClipId(track, clip, position),
      start: position,
      duration: clip.duration - firstDuration,
      sourceStart: clip.sourceStart + firstDuration,
    );
    final tracks = projectController.tracks
        .map(
          (item) => item.id == trackId
              ? item.copyWith(
                  clips: [
                    ...item.clips.where((clip) => clip.id != clipId),
                    clip.copyWith(duration: firstDuration),
                    second,
                  ],
                )
              : item,
        )
        .toList();
    final after = projectController.project.copyWith(tracks: tracks);
    _apply(after, SplitClipCommand(projectController, projectController.project, after));
  }

  /// Moves a clip and shifts following clips on its source track by the delta.
  void rippleMove({required String trackId, required String clipId, required Duration start}) {
    final track = _track(trackId);
    if (track == null) return;

    final clip = _clip(track, clipId);
    if (clip == null) return;
    if (track.locked || clip.locked) return;

    final target = snap(start, excludingClipId: clipId);
    final delta = target - clip.start;
    final updated = track.copyWith(
      clips: track.clips
          .map(
            (item) => item.id == clipId
                ? item.copyWith(start: target)
                : item.start >= clip.start
                    ? item.copyWith(start: item.start + delta)
                    : item,
          )
          .toList(),
    );
    final after = projectController.project.copyWith(
      tracks: projectController.tracks
          .map((item) => item.id == trackId ? updated : item)
          .toList(),
    );
    _apply(after, RippleMoveCommand(projectController, projectController.project, after));
  }

  String _splitClipId(TimelineTrack track, TimelineClip clip, Duration position) {
    final baseId = '${clip.id}_${position.inMilliseconds}';
    final existingIds = track.clips.map((item) => item.id).toSet();
    if (!existingIds.contains(baseId)) return baseId;

    var suffix = 1;
    while (existingIds.contains('${baseId}_$suffix')) {
      suffix++;
    }
    return '${baseId}_$suffix';
  }

  /// Returns a trimmed immutable clip, preserving the source offset for media.
  TimelineClip trimClip({required String trackId, required String clipId, required Duration start, required Duration end, bool recordHistory = true}) {
    final track = _track(trackId); final clip = track == null ? null : _clip(track, clipId);
    if (track == null || clip == null || track.locked || clip.locked) return clip ?? const TimelineClip(id: '', type: ClipType.video, start: Duration.zero, duration: Duration.zero);
    final min = const Duration(milliseconds: 200);
    var newStart = start < Duration.zero ? Duration.zero : start;
    var newEnd = end;
    if (newEnd - newStart < min) { if (start != clip.start) newStart = newEnd - min; else newEnd = newStart + min; }
    if (newStart < Duration.zero) newStart = Duration.zero;
    final sourceDelta = newStart - clip.start;
    if (clip.sourceDuration != null && clip.sourceStart + sourceDelta + (newEnd - newStart) > clip.sourceDuration!) newEnd = clip.sourceDuration! - clip.sourceStart - sourceDelta + newStart;
    final trimmed = clip.copyWith(start: newStart, duration: newEnd - newStart, sourceStart: clip.sourceStart + sourceDelta);
    final after = projectController.project.copyWith(tracks: projectController.tracks.map((t) => t.id == trackId ? t.copyWith(clips: t.clips.map((c) => c.id == clipId ? trimmed : c).toList()) : t).toList());
    _apply(after, recordHistory ? TrimClipCommand(projectController, projectController.project, after) : null); return trimmed;
  }
  void _apply(EditorProject after, EditorCommand? command) {
    if (command != null) {
      history.execute(command);
    } else {
      projectController.updateProject(after);
    }
  }

  Duration snap(Duration value, {String? excludingClipId}) {
    final candidates = <Duration>[Duration.zero, projectController.project.duration, _position];
    for (final track in projectController.tracks) { for (final clip in track.clips) { if (clip.id != excludingClipId) { candidates..add(clip.start)..add(clip.start + clip.duration); } } }
    final nearest = candidates.reduce((a, b) => (a - value).abs() < (b - value).abs() ? a : b);
    return (nearest - value).abs() <= Duration(milliseconds: (snapDistance / pixelsPerSecond * 1000).round()) ? nearest : value < Duration.zero ? Duration.zero : value;
  }

  TimelineTrack? _track(String id) { for (final track in projectController.tracks) { if (track.id == id) return track; } return null; }
  TimelineClip? _clip(TimelineTrack track, String id) { for (final clip in track.clips) { if (clip.id == id) return clip; } return null; }
  bool _accepts(TimelineTrack track, TimelineClip? clip) => clip != null && (track.type == TrackType.audio ? clip.type == ClipType.audio : clip.type != ClipType.audio);

  void reset() {
    _position = Duration.zero;
    _trimStart = Duration.zero;
    _trimEnd = const Duration(minutes: 1);
    pixelsPerSecond = 80;

    notifyListeners();
  }
  @override void dispose() { history.dispose(); super.dispose(); }
}

class TimelineZoom {
  static const List<double> levels = [20, 40, 80, 160, 320, 640];
}
