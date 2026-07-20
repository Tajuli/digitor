import 'package:digitor/features/editor/domain/models/clip_type.dart';
import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:digitor/features/editor/domain/models/timeline_clip.dart';
import 'package:digitor/features/editor/domain/models/timeline_track.dart';
import 'package:digitor/features/editor/domain/models/track_type.dart';
import 'package:digitor/features/editor/domain/models/track_order.dart';
import 'package:digitor/features/editor/domain/models/clip_adjustments.dart';
import 'package:flutter/foundation.dart';

/// Owns project selection and enforces the track/clip compatibility boundary.
class ProjectController extends ChangeNotifier {
  ProjectController({required EditorProject project}) : _project = project.copyWith(tracks: normalizeTrackOrder(project.tracks));

  EditorProject _project;
  int _idSequence = 0;
  String? _selectedTrackId;
  String? _selectedClipId;

  EditorProject get project => _project;
  List<TimelineTrack> get tracks => _project.tracks;
  String? get selectedTrackId => _selectedTrackId;
  String? get selectedClipId => _selectedClipId;
  bool get hasClips => _project.tracks.any((track) => track.clips.isNotEmpty);
  bool isClipSelected(String clipId) => _selectedClipId == clipId;
  bool isTrackSelected(String trackId) => _selectedTrackId == trackId;

  void updateProject(EditorProject project) {
    final normalized = normalizeTrackOrder(project.tracks);
    final calculatedDuration = normalized
        .expand((track) => track.clips)
        .fold(Duration.zero, (end, clip) {
      final clipEnd = clip.start + clip.duration;
      return clipEnd > end ? clipEnd : end;
    });
    _project = project.copyWith(
      tracks: normalized,
      duration: calculatedDuration,
    );
    notifyListeners();
  }
  void selectTrack(String? trackId) { _selectedTrackId = trackId; _selectedClipId = null; notifyListeners(); }
  void selectClip({required String trackId, required String clipId}) { _selectedTrackId = trackId; _selectedClipId = clipId; notifyListeners(); }
  void clearSelection() { if (_selectedTrackId == null && _selectedClipId == null) return; _selectedTrackId = null; _selectedClipId = null; notifyListeners(); }

  String newId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';

  TimelineTrack addVideoTrack() => _addTrack(TrackType.video);
  TimelineTrack addAudioTrack() => _addTrack(TrackType.audio);

  TimelineTrack _addAudioTrackWithNumber(int number) {
    final track = TimelineTrack(
      id: newId('audio'),
      name: 'Audio $number',
      type: TrackType.audio,
    );
    updateProject(_project.copyWith(tracks: [...tracks, track]));
    return track;
  }
  TimelineTrack _addTrack(TrackType type) {
    final count = tracks.where((track) => track.type == type).length + 1;
    final track = TimelineTrack(id: newId(type.name), name: '${type == TrackType.video ? 'Video' : 'Audio'} $count', type: type);
    final next = type == TrackType.video
        ? [
            track,
            ...tracks.where((item) => item.type == TrackType.video),
            ...tracks.where((item) => item.type == TrackType.audio),
          ]
        : [...tracks, track];
    updateProject(_project.copyWith(tracks: next));
    return track;
  }
  void addTrack(TimelineTrack track) => updateProject(_project.copyWith(tracks: [...tracks, track]));
  void removeTrack(String trackId) {
    updateProject(_project.copyWith(tracks: tracks.where((track) => track.id != trackId).toList()));
    if (_selectedTrackId == trackId) clearSelection();
  }

  bool acceptsClip(String trackId, TimelineClip clip) {
    final track = tracks.where((item) => item.id == trackId).firstOrNull;
    return track != null && !track.locked && (track.type == TrackType.audio ? clip.type == ClipType.audio : clip.type != ClipType.audio);
  }
  bool addClip({required String trackId, required TimelineClip clip}) {
    if (!acceptsClip(trackId, clip)) return false;
    final updatedTracks = tracks.map((track) => track.id == trackId ? track.copyWith(clips: [...track.clips, clip]) : track).toList();
    final end = clip.start + clip.duration;
    updateProject(_project.copyWith(tracks: updatedTracks, duration: end > _project.duration ? end : _project.duration));
    return true;
  }

  TimelineClip addImageClip({required String trackId, required String path, required Duration duration, Duration start = Duration.zero}) => _addTypedClip(trackId, ClipType.image, path: path, duration: duration, start: start);
  TimelineClip addTextClip({required String trackId, required String text, Duration duration = const Duration(seconds: 3), Duration start = Duration.zero}) => _addTypedClip(trackId, ClipType.text, duration: duration, start: start, data: {'text': text});
  TimelineClip addOverlayClip({required String trackId, required String path, required Duration duration, Duration start = Duration.zero}) => _addTypedClip(trackId, ClipType.overlay, path: path, duration: duration, start: start);
  TimelineClip addAudioClip({required String trackId, required String path, required Duration duration, Duration start = Duration.zero}) => _addTypedClip(trackId, ClipType.audio, path: path, duration: duration, start: start);
  TimelineClip _addTypedClip(String trackId, ClipType type, {String? path, required Duration duration, required Duration start, Map<String, dynamic> data = const {}}) {
    final clip = TimelineClip(id: newId(type.name), type: type, start: start, duration: duration, sourceDuration: duration, data: {...data, if (path != null) 'path': path});
    if (!addClip(trackId: trackId, clip: clip)) throw ArgumentError('Track does not accept ${type.name} clips.');
    return clip;
  }

  /// Adds the visual clip and, when [hasAudio] is true, an aligned audio clip
  /// referencing the same media path. The audio stream is not extracted.
  ///
  /// A video added to `Video N` always places its embedded audio on `Audio N`.
  /// If `Audio N` already contains clips, every occupied audio track from N
  /// downward is shifted by one track first. Existing clip data and link groups
  /// are preserved; only the owning track changes.
  List<TimelineClip> addVideoWithLinkedAudio({
    required String videoTrackId,
    required String path,
    required Duration duration,
    required bool hasAudio,
    Duration start = Duration.zero,
  }) {
    final video = TimelineClip(
      id: newId('video'),
      type: ClipType.video,
      start: start,
      duration: duration,
      sourceDuration: duration,
      data: {'path': path},
    );

    if (!acceptsClip(videoTrackId, video)) {
      throw ArgumentError('Video track is unavailable.');
    }

    if (!hasAudio) {
      addClip(trackId: videoTrackId, clip: video);
      return [video];
    }

    final preferredNumber = _preferredAudioTrackNumber(videoTrackId);
    final preparedTracks = _prepareMatchingAudioTrack(preferredNumber);
    final audioTrack = preparedTracks.firstWhere(
      (track) =>
          track.type == TrackType.audio &&
          _trackNumber(track.name) == preferredNumber,
    );

    final group = newId('link');
    final linkedVideo = video.copyWith(linkGroupId: group);
    final audio = TimelineClip(
      id: newId('audio'),
      type: ClipType.audio,
      start: start,
      duration: duration,
      sourceDuration: duration,
      linkGroupId: group,
      data: {'path': path},
    );

    final updatedTracks = preparedTracks.map((track) {
      if (track.id == videoTrackId) {
        return track.copyWith(clips: [...track.clips, linkedVideo]);
      }
      if (track.id == audioTrack.id) {
        return track.copyWith(clips: [...track.clips, audio]);
      }
      return track;
    }).toList();

    final end = start + duration;
    updateProject(
      _project.copyWith(
        tracks: updatedTracks,
        duration: end > _project.duration ? end : _project.duration,
      ),
    );
    return [linkedVideo, audio];
  }

  int _preferredAudioTrackNumber(String videoTrackId) {
    final videoTrack = tracks.firstWhere((track) => track.id == videoTrackId);
    final videoTracksBottomUp = tracks
        .where((track) => track.type == TrackType.video)
        .toList()
        .reversed
        .toList();
    final fallbackNumber =
        videoTracksBottomUp.indexWhere((track) => track.id == videoTrackId) + 1;
    return _trackNumber(videoTrack.name) ?? fallbackNumber;
  }

  List<TimelineTrack> _prepareMatchingAudioTrack(int preferredNumber) {
    final videoTracks =
        tracks.where((track) => track.type == TrackType.video).toList();
    final audioTracks =
        tracks.where((track) => track.type == TrackType.audio).toList();

    final byNumber = <int, TimelineTrack>{};
    for (final track in audioTracks) {
      final number = _trackNumber(track.name);
      if (number != null) byNumber[number] = track;
    }

    byNumber.putIfAbsent(
      preferredNumber,
      () => TimelineTrack(
        id: newId('audio'),
        name: 'Audio $preferredNumber',
        type: TrackType.audio,
      ),
    );

    if (byNumber[preferredNumber]!.clips.isNotEmpty) {
      var firstEmpty = preferredNumber + 1;
      while (byNumber[firstEmpty]?.clips.isNotEmpty ?? false) {
        firstEmpty++;
      }

      byNumber.putIfAbsent(
        firstEmpty,
        () => TimelineTrack(
          id: newId('audio'),
          name: 'Audio $firstEmpty',
          type: TrackType.audio,
        ),
      );

      for (var number = firstEmpty; number > preferredNumber; number--) {
        final source = byNumber[number - 1];
        if (source == null) continue;

        final destination = byNumber.putIfAbsent(
          number,
          () => TimelineTrack(
            id: newId('audio'),
            name: 'Audio $number',
            type: TrackType.audio,
          ),
        );

        byNumber[number] = destination.copyWith(clips: source.clips);
        byNumber[number - 1] = source.copyWith(clips: const []);
      }
    }

    final orderedAudioNumbers = byNumber.keys.toList()..sort();
    return [
      ...videoTracks,
      for (final number in orderedAudioNumbers) byNumber[number]!,
    ];
  }

  int? _trackNumber(String name) {
    final match = RegExp(r'(\d+)\s*$').firstMatch(name);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  List<TimelineClip> getLinkedClips(String clipId) {
    final clip = tracks.expand((track) => track.clips).where((item) => item.id == clipId).firstOrNull;
    if (clip?.linkGroupId == null) return const [];
    return tracks.expand((track) => track.clips).where((item) => item.linkGroupId == clip!.linkGroupId).toList();
  }
  bool isLinked(String clipId) => getLinkedClips(clipId).length > 1;
  void linkClips({required String firstClipId, required String secondClipId}) {
    final clips = tracks.expand((track) => track.clips).where((clip) => clip.id == firstClipId || clip.id == secondClipId).toList();
    if (clips.length != 2 || clips[0].type == clips[1].type) throw ArgumentError('Link one visual clip and one audio clip.');
    final group = newId('link');
    _replaceClips({for (final clip in clips) clip.id: clip.copyWith(linkGroupId: group)});
  }
  void unlinkClipGroup(String linkGroupId) {
    final linked = tracks.expand((track) => track.clips).where((clip) => clip.linkGroupId == linkGroupId).toList();
    if (linked.isEmpty) return;
    _replaceClips({for (final clip in linked) clip.id: clip.copyWith(clearLinkGroupId: true)});
  }
  void removeLinkedPair(String clipId) {
    final linked = getLinkedClips(clipId);
    final ids = (linked.isEmpty ? [clipId] : linked.map((clip) => clip.id)).toSet();
    updateProject(_project.copyWith(
      tracks: tracks
          .map((track) => track.copyWith(
                clips: track.clips.where((clip) => !ids.contains(clip.id)).toList(),
              ))
          .toList(),
    ));
    if (ids.contains(_selectedClipId)) clearSelection();
  }
  void removeClip({required String trackId, required String clipId}) {
    final removed = _trackFor(clipId)?.clips.where((clip) => clip.id == clipId).firstOrNull;
    updateProject(_project.copyWith(tracks: tracks.map((track) => track.id == trackId ? track.copyWith(clips: track.clips.where((clip) => clip.id != clipId).toList()) : track).toList()));
    if (removed?.linkGroupId != null) {
      final group = removed!.linkGroupId;
      _replaceClips({
        for (final clip in tracks.expand((track) => track.clips).where((clip) => clip.linkGroupId == group))
          clip.id: clip.copyWith(clearLinkGroupId: true),
      });
    }
    if (_selectedClipId == clipId) clearSelection();
  }
  void updateClip({required String trackId, required TimelineClip clip}) => _replaceClips({clip.id: clip});
  TimelineClip? get selectedClip => _selectedClipId == null ? null : tracks.expand((track) => track.clips).where((clip) => clip.id == _selectedClipId).firstOrNull;
  bool supportsVisualTools(TimelineClip? clip) => clip != null && clip.type != ClipType.audio;
  bool supportsAudioControls(TimelineClip? clip) => clip?.type == ClipType.audio;
  void setFilter(String clipId, ClipFilterType filter) => _updateSelectedClip(clipId, (clip) => clip.copyWith(filter: filter));
  void setEffect(String clipId, ClipEffectType effect) => _updateSelectedClip(clipId, (clip) => clip.copyWith(effect: effect));
  void setColor(String clipId, ClipColorAdjustments value) => _updateSelectedClip(clipId, (clip) => clip.copyWith(colorAdjustments: value));
  void setMuted(String clipId, bool muted) => _updateSelectedClip(clipId, (clip) => clip.copyWith(muted: muted));
  void _updateSelectedClip(String clipId, TimelineClip Function(TimelineClip) transform) {
    final track = _trackFor(clipId); final clip = track?.clips.where((item) => item.id == clipId).firstOrNull;
    if (track == null || clip == null || track.locked || clip.locked) return;
    _replaceClips({clipId: transform(clip)});
  }
  TimelineTrack? _trackFor(String clipId) => tracks.where((track) => track.clips.any((clip) => clip.id == clipId)).firstOrNull;
  void _replaceClips(Map<String, TimelineClip> replacements) => updateProject(_project.copyWith(tracks: tracks.map((track) => track.copyWith(clips: track.clips.map((clip) => replacements[clip.id] ?? clip).toList())).toList()));
}
