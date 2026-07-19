import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:digitor/features/editor/domain/models/timeline_clip.dart';
import 'package:digitor/features/editor/domain/models/timeline_track.dart';
import 'package:flutter/foundation.dart';

class ProjectController extends ChangeNotifier {
  EditorProject _project;

  ProjectController({
    required EditorProject project,
  }) : _project = project;

  EditorProject get project => _project;

  List<TimelineTrack> get tracks => _project.tracks;

  // ===========================
  // Selection
  // ===========================

  String? _selectedTrackId;
  String? _selectedClipId;

  String? get selectedTrackId => _selectedTrackId;
  String? get selectedClipId => _selectedClipId;

  bool isClipSelected(String clipId) {
    return _selectedClipId == clipId;
  }

  bool isTrackSelected(String trackId) {
    return _selectedTrackId == trackId;
  }

  void selectTrack(String? trackId) {
    _selectedTrackId = trackId;
    notifyListeners();
  }

  void selectClip({
    required String trackId,
    required String clipId,
  }) {
    _selectedTrackId = trackId;
    _selectedClipId = clipId;
    notifyListeners();
  }

  void clearSelection() {
    _selectedTrackId = null;
    _selectedClipId = null;
    notifyListeners();
  }

  // ===========================
  // Project
  // ===========================

  void updateProject(EditorProject project) {
    _project = project;
    notifyListeners();
  }

  // ===========================
  // Track
  // ===========================

  void addTrack(TimelineTrack track) {
    updateProject(
      _project.copyWith(
        tracks: [..._project.tracks, track],
      ),
    );
  }

  void removeTrack(String trackId) {
    updateProject(
      _project.copyWith(
        tracks: _project.tracks
            .where((e) => e.id != trackId)
            .toList(),
      ),
    );

    if (_selectedTrackId == trackId) {
      clearSelection();
    }
  }

  // ===========================
  // Clip
  // ===========================

  void addClip({
    required String trackId,
    required TimelineClip clip,
  }) {
    final updated = _project.tracks.map((track) {
      if (track.id != trackId) return track;

      return track.copyWith(
        clips: [...track.clips, clip],
      );
    }).toList();

    updateProject(
      _project.copyWith(
        tracks: updated,
      ),
    );
  }

  void removeClip({
    required String trackId,
    required String clipId,
  }) {
    final updated = _project.tracks.map((track) {
      if (track.id != trackId) return track;

      return track.copyWith(
        clips: track.clips
            .where((c) => c.id != clipId)
            .toList(),
      );
    }).toList();

    updateProject(
      _project.copyWith(
        tracks: updated,
      ),
    );

    if (_selectedClipId == clipId) {
      clearSelection();
    }
  }

  void updateClip({
    required String trackId,
    required TimelineClip clip,
  }) {
    final updated = _project.tracks.map((track) {
      if (track.id != trackId) return track;

      return track.copyWith(
        clips: track.clips
            .map((c) => c.id == clip.id ? clip : c)
            .toList(),
      );
    }).toList();

    updateProject(
      _project.copyWith(
        tracks: updated,
      ),
    );
  }
}
