import 'package:digitor/features/editor/domain/models/clip_type.dart';
import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:digitor/features/editor/domain/models/timeline_clip.dart';
import 'package:digitor/features/editor/domain/models/timeline_track.dart';
import 'package:digitor/features/editor/domain/models/track_type.dart';
import 'package:flutter/foundation.dart';

/// Owns project selection and enforces the track/clip compatibility boundary.
class ProjectController extends ChangeNotifier {
  ProjectController({required EditorProject project}) : _project = project;

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

  void updateProject(EditorProject project) { _project = project; notifyListeners(); }
  void selectTrack(String? trackId) { _selectedTrackId = trackId; _selectedClipId = null; notifyListeners(); }
  void selectClip({required String trackId, required String clipId}) { _selectedTrackId = trackId; _selectedClipId = clipId; notifyListeners(); }
  void clearSelection() { if (_selectedTrackId == null && _selectedClipId == null) return; _selectedTrackId = null; _selectedClipId = null; notifyListeners(); }

  String newId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';

  TimelineTrack addVideoTrack() => _addTrack(TrackType.video);
  TimelineTrack addAudioTrack() => _addTrack(TrackType.audio);
  TimelineTrack _addTrack(TrackType type) {
    final count = tracks.where((track) => track.type == type).length + 1;
    final track = TimelineTrack(id: newId(type.name), name: '${type == TrackType.video ? 'Video' : 'Audio'} $count', type: type);
    updateProject(_project.copyWith(tracks: [...tracks, track]));
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
    if (!addClip(trackId: trackId, clip)) throw ArgumentError('Track does not accept ${type.name} clips.');
    return clip;
  }

  /// Adds the visual clip and, when [hasAudio] is true, an aligned audio clip
  /// referencing the same media path.  The audio stream is not extracted.
  List<TimelineClip> addVideoWithLinkedAudio({required String videoTrackId, required String path, required Duration duration, required bool hasAudio, Duration start = Duration.zero}) {
    final video = TimelineClip(id: newId('video'), type: ClipType.video, start: start, duration: duration, sourceDuration: duration, data: {'path': path});
    if (!acceptsClip(videoTrackId, video)) throw ArgumentError('Video track is unavailable.');
    if (!hasAudio) { addClip(trackId: videoTrackId, clip: video); return [video]; }
    final audioTrack = tracks.where((track) => track.type == TrackType.audio && !track.locked).firstOrNull ?? addAudioTrack();
    final group = newId('link');
    final linkedVideo = video.copyWith(linkGroupId: group);
    final audio = TimelineClip(id: newId('audio'), type: ClipType.audio, start: start, duration: duration, sourceDuration: duration, linkGroupId: group, data: {'path': path});
    addClip(trackId: videoTrackId, clip: linkedVideo);
    addClip(trackId: audioTrack.id, clip: audio);
    return [linkedVideo, audio];
  }

  List<TimelineClip> getLinkedClips(String clipId) {
    final clip = tracks.expand((track) => track.clips).where((item) => item.id == clipId).firstOrNull;
    if (clip?.linkGroupId == null) return const [];
    return tracks.expand((track) => track.clips).where((item) => item.linkGroupId == clip!.linkGroupId).toList();
  }
  void linkClips(String firstClipId, String secondClipId) {
    final clips = tracks.expand((track) => track.clips).where((clip) => clip.id == firstClipId || clip.id == secondClipId).toList();
    if (clips.length != 2 || clips[0].type == clips[1].type) throw ArgumentError('Link one visual clip and one audio clip.');
    final group = newId('link');
    _replaceClips({for (final clip in clips) clip.id: clip.copyWith(linkGroupId: group)});
  }
  void unlinkClipGroup(String clipId) {
    final linked = getLinkedClips(clipId);
    if (linked.isEmpty) return;
    _replaceClips({for (final clip in linked) clip.id: clip.copyWith(clearLinkGroupId: true)});
  }
  void removeLinkedPair(String clipId) { for (final clip in getLinkedClips(clipId)) { removeClip(trackId: _trackFor(clip.id)!.id, clipId: clip.id); } }
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
  TimelineTrack? _trackFor(String clipId) => tracks.where((track) => track.clips.any((clip) => clip.id == clipId)).firstOrNull;
  void _replaceClips(Map<String, TimelineClip> replacements) => updateProject(_project.copyWith(tracks: tracks.map((track) => track.copyWith(clips: track.clips.map((clip) => replacements[clip.id] ?? clip).toList())).toList()));
}
