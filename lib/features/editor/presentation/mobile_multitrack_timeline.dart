import 'dart:math' as math;

import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:flutter/material.dart';

import '../../../core/engine/engine_gateway.dart';

class MobileMultitrackTimeline extends StatefulWidget {
  const MobileMultitrackTimeline({
    super.key,
    required this.snapshot,
    required this.onImport,
    required this.onEdit,
    required this.onSeekUs,
    required this.onTimelineChanged,
  });

  final EngineSnapshot snapshot;
  final VoidCallback onImport;
  final VoidCallback onEdit;
  final ValueChanged<int> onSeekUs;
  final ValueChanged<Map<String, Object?>> onTimelineChanged;

  @override
  State<MobileMultitrackTimeline> createState() =>
      _MobileMultitrackTimelineState();
}

enum _TrackKind { video, audio }

final class _TimelineClipView {
  const _TimelineClipView({
    required this.id,
    required this.path,
    required this.startUs,
    required this.durationUs,
    required this.sourceStartUs,
    required this.sourceGroupId,
  });

  final String id;
  final String path;
  final int startUs;
  final int durationUs;
  final int sourceStartUs;
  final String sourceGroupId;

  int get endUs => startUs + durationUs;
  String get title => path.replaceAll('\\', '/').split('/').last;

  _TimelineClipView copyWith({
    String? id,
    int? startUs,
    int? durationUs,
    int? sourceStartUs,
  }) {
    return _TimelineClipView(
      id: id ?? this.id,
      path: path,
      startUs: startUs ?? this.startUs,
      durationUs: durationUs ?? this.durationUs,
      sourceStartUs: sourceStartUs ?? this.sourceStartUs,
      sourceGroupId: sourceGroupId,
    );
  }
}

class _MobileMultitrackTimelineState extends State<MobileMultitrackTimeline> {
  static const double _headerWidth = 52;
  static const double _rulerHeight = 22;
  static const double _laneHeight = 34;
  static const double _pixelsPerSecond = 48;
  static const int _maxTracksPerType = 32;

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  final List<_TimelineClipView> _clips = <_TimelineClipView>[];

  DigitorTimelineEditingSession? _timeline;
  int _videoTrackCount = 1;
  int _audioTrackCount = 1;
  int _clipSerial = 0;
  int _localPositionUs = 0;
  int _lastObservedImportSerial = -1;
  String? _lastObservedMediaPath;
  String? _selectedClipId;
  String? _timelineError;

  String? get _mediaPath => widget.snapshot.state['mediaPath']?.toString();

  int get _mediaImportSerial {
    final value = widget.snapshot.state['mediaImportSerial'];
    return value is num ? value.toInt() : 0;
  }

  int get _timelineDurationUs {
    var result = 0;
    for (final clip in _clips) {
      if (clip.endUs > result) result = clip.endUs;
    }
    return result;
  }

  List<String> get _trackLabels => <String>[
        for (var index = _videoTrackCount; index >= 1; index--) 'V$index',
        for (var index = 1; index <= _audioTrackCount; index++) 'A$index',
      ];

  _TimelineClipView? get _selectedClip {
    final id = _selectedClipId;
    if (id == null) return null;
    for (final clip in _clips) {
      if (clip.id == id) return clip;
    }
    return null;
  }

  bool get _canSplit {
    final clip = _selectedClip;
    return clip != null &&
        _localPositionUs > clip.startUs &&
        _localPositionUs < clip.endUs;
  }

  @override
  void initState() {
    super.initState();
    _initializeNativeTimeline();
  }

  void _initializeNativeTimeline() {
    try {
      final timeline = DigitorTimelineEditingSession.create();
      timeline.addTrack(
        id: 'V1',
        name: 'Video 1',
        kind: DigitorTimelineTrackKind.video,
      );
      timeline.addTrack(
        id: 'A1',
        name: 'Audio 1',
        kind: DigitorTimelineTrackKind.audio,
      );
      _timeline = timeline;
      _syncImportedMedia();
    } catch (error) {
      _timelineError = '$error';
    }
  }

  @override
  void didUpdateWidget(covariant MobileMultitrackTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPath = oldWidget.snapshot.state['mediaPath']?.toString();
    final newPath = widget.snapshot.state['mediaPath']?.toString();
    final oldSerial = oldWidget.snapshot.state['mediaImportSerial'];
    final newSerial = widget.snapshot.state['mediaImportSerial'];
    if (oldSerial != newSerial ||
        oldPath != newPath ||
        (_clips.isEmpty && newPath != null)) {
      _syncImportedMedia();
    }

    final statusPosition = widget.snapshot.position.inMicroseconds;
    if (statusPosition >= 0 && statusPosition <= _timelineDurationUs) {
      _localPositionUs = statusPosition;
    }
  }

  void _syncImportedMedia() {
    final timeline = _timeline;
    final path = _mediaPath;
    final durationUs = widget.snapshot.duration.inMicroseconds;
    final importSerial = _mediaImportSerial;
    final alreadyObserved = importSerial > 0
        ? importSerial == _lastObservedImportSerial
        : path == _lastObservedMediaPath;
    if (timeline == null ||
        path == null ||
        path.isEmpty ||
        durationUs <= 0 ||
        alreadyObserved) {
      return;
    }

    final serial = ++_clipSerial;
    final clipId = 'video-$serial';
    final audioId = 'audio-$serial';
    final sourceGroup = 'media-$serial';
    final linkGroup = 'av-$serial';
    final startUs = _timelineDurationUs;

    try {
      timeline.addClip(
        trackId: 'V1',
        clipId: clipId,
        kind: DigitorTimelineClipKind.video,
        startUs: startUs,
        durationUs: durationUs,
        sourceDurationUs: durationUs,
        sourceMediaGroupId: sourceGroup,
        linkGroupId: linkGroup,
        embeddedAudio: true,
      );
      timeline.addClip(
        trackId: 'A1',
        clipId: audioId,
        kind: DigitorTimelineClipKind.audio,
        startUs: startUs,
        durationUs: durationUs,
        sourceDurationUs: durationUs,
        sourceMediaGroupId: sourceGroup,
        linkGroupId: linkGroup,
      );
      if (!timeline.info.valid) {
        throw StateError('Native timeline is invalid after media import.');
      }
      if (!mounted) return;
      setState(() {
        _clips.add(
          _TimelineClipView(
            id: clipId,
            path: path,
            startUs: startUs,
            durationUs: durationUs,
            sourceStartUs: 0,
            sourceGroupId: sourceGroup,
          ),
        );
        _lastObservedImportSerial = importSerial;
        _lastObservedMediaPath = path;
        _selectedClipId = clipId;
        _localPositionUs = startUs;
        _timelineError = null;
      });
      _publishTimeline();
      widget.onSeekUs(startUs);
    } catch (error) {
      if (mounted) setState(() => _timelineError = '$error');
    }
  }

  void _publishTimeline() {
    final timeline = _timeline;
    if (timeline == null || _clips.isEmpty) return;
    try {
      final info = timeline.info;
      if (!info.valid || info.durationUs <= 0) {
        throw StateError('Native project timeline is invalid.');
      }
      final sources = <String, String>{};
      for (final clip in _clips) {
        sources[clip.sourceGroupId] = clip.path;
      }
      widget.onTimelineChanged(<String, Object?>{
        'serializedProject': timeline.serialize(),
        'revision': info.revision,
        'durationUs': info.durationUs,
        'videoTrackCount': info.videoTrackCount,
        'audioTrackCount': info.audioTrackCount,
        'fpsNum': 30,
        'fpsDen': 1,
        'sources': <Map<String, Object?>>[
          for (final entry in sources.entries)
            <String, Object?>{
              'sourceMediaGroupId': entry.key,
              'path': entry.value,
            },
        ],
      });
    } catch (error) {
      if (mounted) setState(() => _timelineError = '$error');
    }
  }

  @override
  void dispose() {
    _timeline?.dispose();
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _addTrack(_TrackKind kind) {
    final timeline = _timeline;
    if (timeline == null) return;
    try {
      switch (kind) {
        case _TrackKind.video:
          if (_videoTrackCount >= _maxTracksPerType) return;
          final next = _videoTrackCount + 1;
          timeline.addTrack(
            id: 'V$next',
            name: 'Video $next',
            kind: DigitorTimelineTrackKind.video,
          );
          setState(() => _videoTrackCount = next);
          break;
        case _TrackKind.audio:
          if (_audioTrackCount >= _maxTracksPerType) return;
          final next = _audioTrackCount + 1;
          timeline.addTrack(
            id: 'A$next',
            name: 'Audio $next',
            kind: DigitorTimelineTrackKind.audio,
          );
          setState(() => _audioTrackCount = next);
          break;
      }
      _publishTimeline();
    } catch (error) {
      setState(() => _timelineError = '$error');
    }
  }

  void _splitSelected() {
    final timeline = _timeline;
    final selected = _selectedClip;
    if (timeline == null || selected == null || !_canSplit) return;

    final secondId = 'video-${++_clipSerial}';
    final firstDuration = _localPositionUs - selected.startUs;
    final secondDuration = selected.durationUs - firstDuration;
    try {
      timeline.splitClip(
        clipId: selected.id,
        positionUs: _localPositionUs,
        secondClipId: secondId,
        splitLinked: true,
      );
      if (!timeline.info.valid) {
        throw StateError('Native timeline is invalid after split.');
      }
      final index = _clips.indexWhere((clip) => clip.id == selected.id);
      if (index < 0) return;
      setState(() {
        _clips[index] = selected.copyWith(durationUs: firstDuration);
        _clips.insert(
          index + 1,
          selected.copyWith(
            id: secondId,
            startUs: _localPositionUs,
            durationUs: secondDuration,
            sourceStartUs: selected.sourceStartUs + firstDuration,
          ),
        );
        _selectedClipId = secondId;
        _timelineError = null;
      });
      _publishTimeline();
    } catch (error) {
      setState(() => _timelineError = '$error');
    }
  }

  void _deleteSelected() {
    final timeline = _timeline;
    final selected = _selectedClip;
    if (timeline == null || selected == null) return;
    try {
      timeline.removeClip(selected.id, removeLinked: true);
      if (!timeline.info.valid) {
        throw StateError('Native timeline is invalid after delete.');
      }
      setState(() {
        _clips.removeWhere((clip) => clip.id == selected.id);
        _selectedClipId = null;
        final durationUs = _timelineDurationUs;
        if (_localPositionUs > durationUs) _localPositionUs = durationUs;
        _timelineError = null;
      });
      if (_clips.isNotEmpty) _publishTimeline();
      widget.onSeekUs(_localPositionUs);
    } catch (error) {
      setState(() => _timelineError = '$error');
    }
  }

  void _seek(double x, double contentWidth) {
    final durationUs = _timelineDurationUs;
    if (durationUs <= 0 || contentWidth <= 0) return;
    final fraction = (x / contentWidth).clamp(0.0, 1.0).toDouble();
    final globalUs = (durationUs * fraction).round();
    setState(() => _localPositionUs = globalUs);

    // Project timeline time is authoritative. Native production resolves the
    // active clip and converts this to source-local time; Flutter never seeks a
    // decoder directly and never performs pixel processing.
    widget.onSeekUs(globalUs);
  }

  List<_TimelineClipView> _clipsForTrack(String label) {
    if (label == 'V1' || label == 'A1') return _clips;
    return const <_TimelineClipView>[];
  }

  @override
  Widget build(BuildContext context) {
    final labels = _trackLabels;
    final durationUs = _timelineDurationUs;
    final duration = Duration(microseconds: durationUs);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B0B0F),
        border: Border(
          top: BorderSide(color: Color(0xFF24242A)),
          bottom: BorderSide(color: Color(0xFF17171C)),
        ),
      ),
      child: Column(
        children: <Widget>[
          _TimelineToolbar(
            position: Duration(microseconds: _localPositionUs),
            onImport: widget.onImport,
            onEdit: widget.onEdit,
            onAddTrack: _addTrack,
            onSplit: _canSplit ? _splitSelected : null,
            onDelete: _selectedClip == null ? null : _deleteSelected,
            canAddVideo: _videoTrackCount < _maxTracksPerType,
            canAddAudio: _audioTrackCount < _maxTracksPerType,
          ),
          if (_timelineError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              color: const Color(0xFF3A1616),
              child: Text(
                _timelineError!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFFFB4B4), fontSize: 9),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewportWidth = math.max(
                  1.0,
                  constraints.maxWidth - _headerWidth,
                );
                final requestedWidth = durationUs <= 0
                    ? viewportWidth * 1.5
                    : (durationUs / 1000000.0) * _pixelsPerSecond;
                final contentWidth = math.max(viewportWidth, requestedWidth);
                final playheadX = durationUs <= 0
                    ? 0.0
                    : (_localPositionUs / durationUs)
                            .clamp(0.0, 1.0)
                            .toDouble() *
                        contentWidth;
                final contentHeight = _rulerHeight + labels.length * _laneHeight;

                return SingleChildScrollView(
                  controller: _verticalController,
                  scrollDirection: Axis.vertical,
                  child: SizedBox(
                    height: contentHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: _headerWidth,
                          child: Column(
                            children: <Widget>[
                              const SizedBox(height: _rulerHeight),
                              for (final label in labels)
                                _TrackHeader(
                                  label: label,
                                  hasClip: _clipsForTrack(label).isNotEmpty,
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _horizontalController,
                            scrollDirection: Axis.horizontal,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) =>
                                  _seek(details.localPosition.dx, contentWidth),
                              onHorizontalDragUpdate: (details) =>
                                  _seek(details.localPosition.dx, contentWidth),
                              child: SizedBox(
                                width: contentWidth,
                                height: contentHeight,
                                child: Stack(
                                  children: <Widget>[
                                    Column(
                                      children: <Widget>[
                                        _TimelineRuler(
                                          width: contentWidth,
                                          duration: duration,
                                        ),
                                        for (final label in labels)
                                          _TimelineLane(
                                            label: label,
                                            contentWidth: contentWidth,
                                            durationUs: durationUs,
                                            clips: _clipsForTrack(label),
                                            selectedClipId: _selectedClipId,
                                            audioLane: label == 'A1',
                                            onClipTap: (id) => setState(
                                              () => _selectedClipId = id,
                                            ),
                                            onEmptyTap: label == 'V1'
                                                ? widget.onImport
                                                : null,
                                          ),
                                      ],
                                    ),
                                    Positioned(
                                      left: playheadX - 0.75,
                                      top: _rulerHeight,
                                      bottom: 0,
                                      child: IgnorePointer(
                                        child: Container(
                                          width: 1.5,
                                          color: const Color(0xFFFF4D4D),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: (playheadX - 8)
                                          .clamp(
                                            0.0,
                                            math.max(0.0, contentWidth - 16),
                                          )
                                          .toDouble(),
                                      top: 0,
                                      child: const IgnorePointer(
                                        child: Icon(
                                          Icons.arrow_drop_down,
                                          size: 18,
                                          color: Color(0xFFFF4D4D),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineToolbar extends StatelessWidget {
  const _TimelineToolbar({
    required this.position,
    required this.onImport,
    required this.onEdit,
    required this.onAddTrack,
    required this.onSplit,
    required this.onDelete,
    required this.canAddVideo,
    required this.canAddAudio,
  });

  final Duration position;
  final VoidCallback onImport;
  final VoidCallback onEdit;
  final ValueChanged<_TrackKind> onAddTrack;
  final VoidCallback? onSplit;
  final VoidCallback? onDelete;
  final bool canAddVideo;
  final bool canAddAudio;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 4),
          _ToolbarButton(
            icon: Icons.video_call_outlined,
            label: 'Add',
            onTap: onImport,
          ),
          _ToolbarButton(
            icon: Icons.content_cut,
            label: 'Split',
            onTap: onSplit,
          ),
          _ToolbarButton(
            icon: Icons.delete_outline,
            label: 'Delete',
            onTap: onDelete,
          ),
          PopupMenuButton<_TrackKind>(
            tooltip: 'Add track',
            enabled: canAddVideo || canAddAudio,
            color: const Color(0xFF17171C),
            onSelected: onAddTrack,
            itemBuilder: (_) => <PopupMenuEntry<_TrackKind>>[
              PopupMenuItem(
                value: _TrackKind.video,
                enabled: canAddVideo,
                child: const Text('Add video track'),
              ),
              PopupMenuItem(
                value: _TrackKind.audio,
                enabled: canAddAudio,
                child: const Text('Add audio track'),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 7),
              child: Icon(Icons.add, size: 18, color: Color(0xFFD9D9E0)),
            ),
          ),
          const Spacer(),
          Text(
            _formatDuration(position),
            style: const TextStyle(color: Color(0xFFB9B9C2), fontSize: 10),
          ),
          _ToolbarButton(icon: Icons.tune, label: 'Edit', onTap: onEdit),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 15,
              color: enabled
                  ? const Color(0xFFD9D9E0)
                  : const Color(0xFF55555E),
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: enabled
                    ? const Color(0xFFB9B9C2)
                    : const Color(0xFF55555E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({required this.label, required this.hasClip});

  final String label;
  final bool hasClip;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _MobileMultitrackTimelineState._laneHeight,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Color(0xFF232329)),
          bottom: BorderSide(color: Color(0xFF19191F)),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: hasClip ? const Color(0xFFE0E0E6) : const Color(0xFF777781),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TimelineLane extends StatelessWidget {
  const _TimelineLane({
    required this.label,
    required this.contentWidth,
    required this.durationUs,
    required this.clips,
    required this.selectedClipId,
    required this.audioLane,
    required this.onClipTap,
    required this.onEmptyTap,
  });

  final String label;
  final double contentWidth;
  final int durationUs;
  final List<_TimelineClipView> clips;
  final String? selectedClipId;
  final bool audioLane;
  final ValueChanged<String> onClipTap;
  final VoidCallback? onEmptyTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: clips.isEmpty ? onEmptyTap : null,
      child: Container(
        height: _MobileMultitrackTimelineState._laneHeight,
        decoration: const BoxDecoration(
          color: Color(0xFF101015),
          border: Border(bottom: BorderSide(color: Color(0xFF1C1C22))),
        ),
        child: Stack(
          children: <Widget>[
            for (final clip in clips) _buildClip(clip),
          ],
        ),
      ),
    );
  }

  Widget _buildClip(_TimelineClipView clip) {
    final safeDuration = math.max(1, durationUs);
    final left = clip.startUs / safeDuration * contentWidth;
    final width = math.max(
      14.0,
      clip.durationUs / safeDuration * contentWidth - 2,
    );
    final selected = selectedClipId == clip.id;
    return Positioned(
      left: left + 1,
      top: 2,
      bottom: 2,
      width: width,
      child: GestureDetector(
        onTap: audioLane ? null : () => onClipTap(clip.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: audioLane
                ? const Color(0xFF28573D)
                : const Color(0xFF2D4772),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected && !audioLane
                  ? Colors.white
                  : const Color(0xFF4B5D78),
              width: selected && !audioLane ? 1.5 : 0.6,
            ),
          ),
          child: Text(
            audioLane ? 'Audio · ${clip.title}' : clip.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFF2F2F5), fontSize: 9),
          ),
        ),
      ),
    );
  }
}

class _TimelineRuler extends StatelessWidget {
  const _TimelineRuler({required this.width, required this.duration});

  final double width;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final seconds = math.max(1, duration.inSeconds);
    final step = seconds <= 15
        ? 1
        : seconds <= 60
            ? 5
            : 10;
    return SizedBox(
      height: _MobileMultitrackTimelineState._rulerHeight,
      child: Stack(
        children: <Widget>[
          for (var second = 0; second <= seconds; second += step)
            Positioned(
              left: second / seconds * width,
              top: 0,
              child: Text(
                _formatDuration(Duration(seconds: second)),
                style: const TextStyle(color: Color(0xFF777781), fontSize: 8),
              ),
            ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final totalMs = value.inMilliseconds.abs();
  final minutes = totalMs ~/ 60000;
  final seconds = (totalMs ~/ 1000) % 60;
  final hundredths = (totalMs % 1000) ~/ 10;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${hundredths.toString().padLeft(2, '0')}';
}
