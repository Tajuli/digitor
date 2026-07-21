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
import '../presentation/timeline/timeline_constants.dart';

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
  bool _magnetEnabled = true;

  Duration _position = Duration.zero;
  Duration _trimStart = Duration.zero;
  Duration _trimEnd = const Duration(minutes: 1);

  Duration get position => _position;
  Duration get trimStart => _trimStart;
  Duration get trimEnd => _trimEnd;

  double get zoom => pixelsPerSecond;
  bool get magnetEnabled => _magnetEnabled;

  void setMagnetEnabled(bool value) {
    if (_magnetEnabled == value) return;
    _magnetEnabled = value;
    notifyListeners();
  }

  /// Changes timeline scale. Very high values allow frame-level positioning,
  /// while very low values allow the whole project to fit in the viewport.
  void setZoom(double pixels) {
    final clamped = pixels.clamp(TimelineZoom.minimum, TimelineZoom.maximum).toDouble();
    if ((pixelsPerSecond - clamped).abs() < 0.001) return;
    pixelsPerSecond = clamped;
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
    setZoom(
      TimelineZoom.levels[
        index < TimelineZoom.levels.length - 1 ? index + 1 : index
      ],
    );
  }

  void zoomOut() {
    final index = _nearestZoomIndex();
    setZoom(TimelineZoom.levels[index > 0 ? index - 1 : index]);
  }

  void fitToWidth(double viewportWidth) {
    if (viewportWidth <= 0) return;
    final durationUs = projectController.project.duration.inMicroseconds;
    if (durationUs <= 0) {
      setZoom(TimelineConstants.pixelsPerSecond);
      return;
    }
    final seconds = durationUs / Duration.microsecondsPerSecond;
    setZoom(viewportWidth / seconds);
  }

  /// Snaps the playhead only to clip boundaries. The current playhead is not
  /// included as a candidate, otherwise dragging could stick to itself.
  Duration snapPlayhead(Duration value) {
    final clamped = TimelineMath.clampTimelinePosition(
      value,
      projectController.project.duration,
    );
    if (!_magnetEnabled) return clamped;

    final candidates = <Duration>[];
    for (final track in projectController.tracks) {
      for (final clip in track.clips) {
        candidates
          ..add(clip.start)
          ..add(clip.start + clip.duration);
      }
    }
    if (candidates.isEmpty) return clamped;

    final nearest = candidates.reduce(
      (a, b) => (a - clamped).abs() <= (b - clamped).abs() ? a : b,
    );
    final threshold = TimelineMath.pixelsToDuration(
      TimelineConstants.playheadSnapThresholdPixels,
      pixelsPerSecond,
    );
    return (nearest - clamped).abs() <= threshold ? nearest : clamped;
  }

  int _nearestZoomIndex() => TimelineZoom.levels.indexOf(
        TimelineZoom.levels.reduce((a, b) =>
            (a - pixelsPerSecond).abs() < (b - pixelsPerSecond).abs() ? a : b),
      );

  /// Import operations insert at the playhead (or zero in an empty project)
  /// and create a single undo snapshot per completed picker action.
  Duration get insertionPosition => snap(_position);
  void addVideoWithLinkedAudio({required String trackId, required String path, required Duration duration, required bool hasAudio}) => _recordProjectMutation(() => projectController.addVideoWithLinkedAudio(videoTrackId: trackId, path: path, duration: duration, hasAudio: hasAudio, start: insertionPosition));
  void addImageClip({required String trackId, required String path, required Duration duration}) => _recordProjectMutation(() => projectController.addImageClip(trackId: trackId, path: path, duration: duration, start: insertionPosition));
  void addOverlayClip({required String trackId, required String path, required Duration duration}) => _recordProjectMutation(() => projectController.addOverlayClip(trackId: trackId, path: path, duration: duration, start: insertionPosition));
  void addTextClip({required String trackId, required String text}) => _recordProjectMutation(() => projectController.addTextClip(trackId: trackId, text: text, start: insertionPosition));
  void addAudioClip({required String trackId, required String path, required Duration duration}) => _recordProjectMutation(() => projectController.addAudioClip(trackId: trackId, path: path, duration: duration, start: insertionPosition));
  void addVideoTrack() => _recordProjectMutation(projectController.addVideoTrack);
  void addAudioTrack() => _recordProjectMutation(projectController.addAudioTrack);
  void unlinkClipGroup(String clipId) { final group = projectController.getLinkedClips(clipId).firstOrNull?.linkGroupId; if (group != null) _recordProjectMutation(() => projectController.unlinkClipGroup(group)); }
  void updateClip(TimelineClip replacement) => _recordProjectMutation(() {
        final track = _trackContaining(replacement.id);
        if (track != null) projectController.updateClip(trackId: track.id, clip: replacement);
      });
  void addClipCopy({required String trackId, required TimelineClip clip}) => _recordProjectMutation(() {
    final copy = clip.copyWith(id: projectController.newId(clip.type.name), start: snap(clip.start + clip.duration));
    projectController.addClip(trackId: trackId, clip: copy);
  });

  void deleteSelectedClip() {
    final clip = projectController.selectedClip;
    final track = clip == null ? null : _trackContaining(clip.id);
    if (clip != null && track != null) _recordProjectMutation(() => projectController.removeLinkedPair(clip.id));
  }
  void _recordProjectMutation(void Function() mutation) { final before = projectController.project; mutation(); final after = projectController.project; if (!identical(before, after)) history.record(ProjectSnapshotCommand(projectController, before, after)); }

  /// Moves a clip, optionally to another compatible track, after magnetic snap.
  void moveClip({required String clipId, required String fromTrackId, required String toTrackId, required Duration start, bool recordHistory = true}) {
    final source = _track(fromTrackId);
    final destination = _track(toTrackId);
    if (source == null || destination == null || source.locked || destination.locked || !_accepts(destination, _clip(source, clipId))) return;
    final clip = _clip(source, clipId)!;
    if (clip.locked) return;
    final target = snap(start, excludingClipId: clipId);
    final linked = projectController.getLinkedClips(clipId);
    if (linked.any((item) => item.locked || _trackContaining(item.id)?.locked == true)) return;
    final delta = target - clip.start;
    final minimumStart = linked.fold<Duration>(clip.start, (minimum, item) => item.start < minimum ? item.start : minimum);
    final adjustedTarget = target - (minimumStart + delta < Duration.zero ? minimumStart + delta : Duration.zero);
    final adjustedDelta = adjustedTarget - clip.start;
    final moved = clip.copyWith(start: adjustedTarget);
    final tracks = projectController.tracks.map((track) {
      if (track.id == fromTrackId && track.id == toTrackId) return track.copyWith(clips: track.clips.map((item) => item.id == clipId ? moved : item).toList());
      if (track.id == fromTrackId) return track.copyWith(clips: track.clips.where((item) => item.id != clipId).toList());
      if (track.id == toTrackId) return track.copyWith(clips: [...track.clips, moved]);
      if (linked.any((item) => item.id != clipId && track.clips.any((existing) => existing.id == item.id))) return track.copyWith(clips: track.clips.map((item) => linked.any((linkedClip) => linkedClip.id == item.id) ? item.copyWith(start: item.start + adjustedDelta) : item).toList());
      return track;
    }).toList();
    if (_hasOverlaps(tracks)) return;
    final after = projectController.project.copyWith(tracks: tracks);
    _apply(after, recordHistory ? MoveClipCommand(projectController, projectController.project, after) : null);
  }


  bool _hasOverlaps(List<TimelineTrack> tracks) {
    for (final track in tracks) {
      final clips = [...track.clips]..sort((a, b) => a.start.compareTo(b.start));
      for (var index = 1; index < clips.length; index++) {
        if (clips[index - 1].start + clips[index - 1].duration > clips[index].start) return true;
      }
    }
    return false;
  }

  /// Splits a clip at [position], preserving the original clip's metadata.
  void splitClip({required String trackId, required String clipId, required Duration position}) {
    final track = _track(trackId);
    if (track == null) return;

    final clip = _clip(track, clipId);
    if (clip == null) return;
    if (track.locked || clip.locked) return;
    if (position <= clip.start || position >= clip.start + clip.duration) return;

    final linked = projectController.getLinkedClips(clipId);
    if (linked.length == 2 && linked.any((item) => item.locked || _trackContaining(item.id)?.locked == true)) return;
    if (linked.length == 2) {
      final firstGroup = projectController.newId('link');
      final secondGroup = projectController.newId('link');
      final replacements = <String, List<TimelineClip>>{};
      for (final item in linked) {
        final splitAt = item.start + (position - clip.start);
        if (splitAt <= item.start || splitAt >= item.start + item.duration) return;
        final firstDuration = splitAt - item.start;
        replacements[item.id] = [
          item.copyWith(duration: firstDuration, linkGroupId: firstGroup),
          item.copyWith(id: _splitClipId(_trackContaining(item.id)!, item, splitAt), start: splitAt, duration: item.duration - firstDuration, sourceStart: item.sourceStart + firstDuration, linkGroupId: secondGroup),
        ];
      }
      final after = projectController.project.copyWith(tracks: projectController.tracks.map((item) => item.copyWith(clips: item.clips.expand((existing) => replacements[existing.id] ?? [existing]).toList())).toList());
      _apply(after, SplitClipCommand(projectController, projectController.project, after));
      return;
    }
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
    var newStart = snap(start, excludingClipId: clipId);
    var newEnd = snap(end, excludingClipId: clipId);
    if (newStart < Duration.zero) newStart = Duration.zero;
    if (newEnd - newStart < min) { if (start != clip.start) newStart = newEnd - min; else newEnd = newStart + min; }
    if (newStart < Duration.zero) newStart = Duration.zero;
    final sourceDelta = newStart - clip.start;
    if (clip.sourceDuration != null && clip.sourceStart + sourceDelta + (newEnd - newStart) > clip.sourceDuration!) newEnd = clip.sourceDuration! - clip.sourceStart - sourceDelta + newStart;
    final trimmed = clip.copyWith(start: newStart, duration: newEnd - newStart, sourceStart: clip.sourceStart + sourceDelta);
    final linked = projectController.getLinkedClips(clipId);
    if (linked.any((item) => item.locked || _trackContaining(item.id)?.locked == true)) return clip;
    final replacements = <String, TimelineClip>{clipId: trimmed};
    if (linked.length == 2) {
      final startDelta = trimmed.start - clip.start;
      final endDelta = (trimmed.start + trimmed.duration) - (clip.start + clip.duration);
      for (final partner in linked.where((item) => item.id != clipId)) {
        final partnerStart = partner.start + startDelta;
        final partnerEnd = partner.start + partner.duration + endDelta;
        replacements[partner.id] = partner.copyWith(start: partnerStart, duration: partnerEnd - partnerStart, sourceStart: partner.sourceStart + startDelta);
      }
    }
    final after = projectController.project.copyWith(tracks: projectController.tracks.map((t) => t.copyWith(clips: t.clips.map((c) => replacements[c.id] ?? c).toList())).toList());
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
    if (!_magnetEnabled) return value < Duration.zero ? Duration.zero : value;
    final candidates = <Duration>[Duration.zero, projectController.project.duration, _position];
    for (final track in projectController.tracks) { for (final clip in track.clips) { if (clip.id != excludingClipId) { candidates..add(clip.start)..add(clip.start + clip.duration); } } }
    final nearest = candidates.reduce((a, b) => (a - value).abs() < (b - value).abs() ? a : b);
    final threshold = TimelineMath.pixelsToDuration(
      TimelineConstants.snapThresholdPixels,
      pixelsPerSecond,
    );
    return (nearest - value).abs() <= threshold
        ? nearest
        : value < Duration.zero
            ? Duration.zero
            : value;
  }

  TimelineTrack? _track(String id) { for (final track in projectController.tracks) { if (track.id == id) return track; } return null; }
  TimelineTrack? _trackContaining(String clipId) { for (final track in projectController.tracks) { if (track.clips.any((clip) => clip.id == clipId)) return track; } return null; }
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
  static const double minimum = 0.5;
  static const double maximum = 3840;
  static const List<double> levels = [
    0.5,
    1,
    2,
    5,
    10,
    20,
    40,
    80,
    160,
    320,
    640,
    1280,
    1920,
    3840,
  ];
}
