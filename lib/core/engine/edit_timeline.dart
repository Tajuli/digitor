final class EditTimelineClip {
  const EditTimelineClip({
    required this.id,
    required this.sourcePath,
    required this.displayName,
    required this.sourceInUs,
    required this.sourceOutUs,
    required this.timelineStartUs,
    required this.frameDurationUs,
    required this.firstFrameNumber,
    required this.width,
    required this.height,
  });

  final String id;
  final String sourcePath;
  final String displayName;
  final int sourceInUs;
  final int sourceOutUs;
  final int timelineStartUs;
  final int frameDurationUs;
  final int firstFrameNumber;
  final int width;
  final int height;

  int get durationUs => sourceOutUs - sourceInUs;
  int get timelineEndUs => timelineStartUs + durationUs;

  bool containsTimelinePosition(int positionUs, {bool includeEnd = false}) {
    if (includeEnd) {
      return positionUs >= timelineStartUs && positionUs <= timelineEndUs;
    }
    return positionUs >= timelineStartUs && positionUs < timelineEndUs;
  }

  int sourceTimestampForTimeline(int positionUs) {
    final offset = (positionUs - timelineStartUs).clamp(0, durationUs);
    return sourceInUs + offset;
  }

  EditTimelineClip copyWith({
    String? id,
    int? sourceInUs,
    int? sourceOutUs,
    int? timelineStartUs,
  }) =>
      EditTimelineClip(
        id: id ?? this.id,
        sourcePath: sourcePath,
        displayName: displayName,
        sourceInUs: sourceInUs ?? this.sourceInUs,
        sourceOutUs: sourceOutUs ?? this.sourceOutUs,
        timelineStartUs: timelineStartUs ?? this.timelineStartUs,
        frameDurationUs: frameDurationUs,
        firstFrameNumber: firstFrameNumber,
        width: width,
        height: height,
      );

  Map<String, Object> toState() => <String, Object>{
        'id': id,
        'sourcePath': sourcePath,
        'displayName': displayName,
        'sourceInUs': sourceInUs,
        'sourceOutUs': sourceOutUs,
        'timelineStartUs': timelineStartUs,
        'durationUs': durationUs,
        'timelineEndUs': timelineEndUs,
        'frameDurationUs': frameDurationUs,
        'firstFrameNumber': firstFrameNumber,
        'width': width,
        'height': height,
      };
}

final class EditTimelineSplitResult {
  const EditTimelineSplitResult({required this.left, required this.right});

  final EditTimelineClip left;
  final EditTimelineClip right;
}

/// Contiguous V1/A1 edit sequence used by the mobile editor.
///
/// Clips retain source in/out ranges while timeline positions are recalculated
/// after structural edits. This keeps split/delete ripple behavior deterministic
/// without coupling UI widgets to decoder state.
final class LinearEditTimeline {
  final List<EditTimelineClip> _clips = <EditTimelineClip>[];
  int _serial = 0;

  List<EditTimelineClip> get clips => List<EditTimelineClip>.unmodifiable(_clips);
  bool get isEmpty => _clips.isEmpty;
  bool get isNotEmpty => _clips.isNotEmpty;
  int get length => _clips.length;
  int get durationUs => _clips.isEmpty ? 0 : _clips.last.timelineEndUs;

  void clear() {
    _clips.clear();
    _serial = 0;
  }

  EditTimelineClip append({
    required String sourcePath,
    required String displayName,
    required int sourceDurationUs,
    required int frameDurationUs,
    required int firstFrameNumber,
    required int width,
    required int height,
  }) {
    if (sourcePath.trim().isEmpty || sourceDurationUs <= 0 || width <= 0 || height <= 0) {
      throw ArgumentError('Valid source path, duration and dimensions are required.');
    }
    final clip = EditTimelineClip(
      id: _nextId(),
      sourcePath: sourcePath,
      displayName: displayName.trim().isEmpty ? 'Video' : displayName.trim(),
      sourceInUs: 0,
      sourceOutUs: sourceDurationUs,
      timelineStartUs: durationUs,
      frameDurationUs: frameDurationUs > 0 ? frameDurationUs : 33333,
      firstFrameNumber: firstFrameNumber,
      width: width,
      height: height,
    );
    _clips.add(clip);
    return clip;
  }

  EditTimelineClip? byId(String? id) {
    if (id == null) return null;
    for (final clip in _clips) {
      if (clip.id == id) return clip;
    }
    return null;
  }

  int indexOfId(String? id) {
    if (id == null) return -1;
    return _clips.indexWhere((clip) => clip.id == id);
  }

  EditTimelineClip? clipAt(int positionUs) {
    if (_clips.isEmpty) return null;
    final clamped = positionUs.clamp(0, durationUs);
    if (clamped == durationUs) return _clips.last;
    for (final clip in _clips) {
      if (clip.containsTimelinePosition(clamped)) return clip;
    }
    return null;
  }

  EditTimelineClip? nextAfter(String? id) {
    final index = indexOfId(id);
    if (index < 0 || index + 1 >= _clips.length) return null;
    return _clips[index + 1];
  }

  bool canSplit(String? id, int timelinePositionUs) {
    final clip = byId(id);
    if (clip == null) return false;
    final guard = clip.frameDurationUs.clamp(1, clip.durationUs ~/ 2);
    return timelinePositionUs >= clip.timelineStartUs + guard &&
        timelinePositionUs <= clip.timelineEndUs - guard;
  }

  EditTimelineSplitResult split(String id, int timelinePositionUs) {
    final index = indexOfId(id);
    if (index < 0) throw StateError('Selected clip no longer exists.');
    final clip = _clips[index];
    if (!canSplit(id, timelinePositionUs)) {
      throw StateError('Move the playhead inside the selected clip before splitting.');
    }

    final sourceSplitUs = clip.sourceTimestampForTimeline(timelinePositionUs);
    final left = clip.copyWith(sourceOutUs: sourceSplitUs);
    final right = clip.copyWith(
      id: _nextId(),
      sourceInUs: sourceSplitUs,
      timelineStartUs: timelinePositionUs,
    );
    _clips
      ..removeAt(index)
      ..insertAll(index, <EditTimelineClip>[left, right]);
    _reflow();
    return EditTimelineSplitResult(
      left: _clips[index],
      right: _clips[index + 1],
    );
  }

  EditTimelineClip delete(String id) {
    final index = indexOfId(id);
    if (index < 0) throw StateError('Selected clip no longer exists.');
    final removed = _clips.removeAt(index);
    _reflow();
    return removed;
  }

  void _reflow() {
    var cursorUs = 0;
    for (var index = 0; index < _clips.length; index++) {
      final clip = _clips[index];
      _clips[index] = clip.copyWith(timelineStartUs: cursorUs);
      cursorUs += clip.durationUs;
    }
  }

  String _nextId() => 'clip-${++_serial}';
}
