import 'dart:async';
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
  });

  final EngineSnapshot snapshot;
  final VoidCallback onImport;
  final VoidCallback onEdit;
  final ValueChanged<int> onSeekUs;

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
  }) =>
      _TimelineClipView(
        id: id ?? this.id,
        path: path,
        startUs: startUs ?? this.startUs,
        durationUs: durationUs ?? this.durationUs,
        sourceStartUs: sourceStartUs ?? this.sourceStartUs,
        sourceGroupId: sourceGroupId,
      );
}

class _MobileMultitrackTimelineState extends State<MobileMultitrackTimeline> {
  static const double _trackHeaderWidth = 54;
  static const double _rulerHeight = 24;
  static const double _trackHeight = 36;
  static const double _pixelsPerSecond = 46;
  static const Color _playheadColor = Color(0xFFFF4D4D);
  static const int _maxTracksPerType = 32;

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  final GlobalKey _contentKey = GlobalKey();
  final List<_TimelineClipView> _clips = <_TimelineClipView>[];

  DigitorTimelineEditingSession? _timeline;
  int _videoTrackCount = 1;
  int _audioTrackCount = 1;
  int _clipSerial = 0;
  int _localPositionUs = 0;
  String? _selectedClipId;
  String? _lastObservedMediaPath;
  String? _timelineError;

  String? get _mediaPath => widget.snapshot.state['mediaPath']?.toString();

  int get _timelineDurationUs {
    var value = 0;
    for (final clip in _clips) value = math.max(value, clip.endUs);
    return value;
  }

  List<String> get _trackLabels => <String>[
        for (int index = _videoTrackCount; index >= 1; index--) 'V$index',
        for (int index = 1; index <= _audioTrackCount; index++) 'A$index',
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
    if (oldPath != newPath || (_clips.isEmpty && newPath != null)) {
      _syncImportedMedia();
    }
    final enginePosition = widget.snapshot.position.inMicroseconds;
    if (_clips.length <= 1 && enginePosition >= 0) {
      _localPositionUs = enginePosition.clamp(0, _timelineDurationUs);
    }
  }

  void _syncImportedMedia() {
    final timeline = _timeline;
    final path = _mediaPath;
    final durationUs = widget.snapshot.duration.inMicroseconds;
    if (timeline == null ||
        path == null ||
        path.isEmpty ||
        durationUs <= 0 ||
        path == _lastObservedMediaPath) {
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
        throw StateError('Native timeline became invalid after media import.');
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
        _lastObservedMediaPath = path;
        _selectedClipId = clipId;
        _localPositionUs = startUs;
        _timelineError = null;
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
    } catch (error) {
      setState(() => _timelineError = '$error');
    }
  }

  void _selectClip(String clipId) {
    setState(() => _selectedClipId = clipId);
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
        throw StateError('Native timeline became invalid after split.');
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
        throw StateError('Native timeline became invalid after delete.');
      }
      setState(() {
        _clips.removeWhere((clip) => clip.id == selected.id);
        _selectedClipId = null;
        _localPositionUs = _localPositionUs.clamp(0, _timelineDurationUs);
        _timelineError = null;
      });
    } catch (error) {
      setState(() => _timelineError = '$error');
    }
  }

  void _seekAt(double x, double contentWidth) {
    final durationUs = _timelineDurationUs;
    if (durationUs <= 0 || contentWidth <= 0) return;
    final fraction = (x / contentWidth).clamp(0.0, 1.0).toDouble();
    final globalUs = (durationUs * fraction).round();
    setState(() => _localPositionUs = globalUs);

    // The existing production session remains engine-owned. Until its source
    // registry consumes the full project, only seek inside the media currently
    // opened by that session; never render pixels in Flutter as a workaround.
    final selected = _selectedClip;
    if (selected != null &&
        globalUs >= selected.startUs &&
        globalUs <= selected.endUs) {
      widget.onSeekUs(selected.sourceStartUs + globalUs - selected.startUs);
    }
  }

  void _seekFromGlobal(Offset globalPosition, double contentWidth) {
    final renderObject = _contentKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    final local = renderObject.globalToLocal(globalPosition);
    _seekAt(local.dx, contentWidth);
  }

  List<_TimelineClipView> _clipsForTrack(String label) {
    if (label == 'V1') return _clips;
    if (label == 'A1') return _clips;
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
                  constraints.maxWidth - _trackHeaderWidth,
                );
                final seconds = durationUs / 1000000.0;
                final requestedWidth = seconds <= 0
                    ? viewportWidth * 1.6
                    : seconds * _pixelsPerSecond;
                final contentWidth = requestedWidth
                    .clamp(viewportWidth, 12000.0)
                    .toDouble();
                final playheadX = durationUs <= 0
                    ? 0.0
                    : (_localPositionUs / durationUs)
                            .clamp(0.0, 1.0)
                            .toDouble() *
                        contentWidth;
                final fullContentHeight =
                    _rulerHeight + labels.length * _trackHeight;

                return Scrollbar(
                  controller: _verticalController,
                  thumbVisibility: labels.length > 4,
                  child: SingleChildScrollView(
                    controller: _verticalController,
                    scrollDirection: Axis.vertical,
                    child: SizedBox(
                      height: fullContentHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: _trackHeaderWidth,
                            child: Column(
                              children: <Widget>[
                                const SizedBox(height: _rulerHeight),
                                for (final label in labels)
                                  _TrackHeader(
                                    label: label,
                                    height: _trackHeight,
                                    hasClip: _clipsForTrack(label).isNotEmpty,
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _horizontalController,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                key: _contentKey,
                                width: contentWidth,
                                height: fullContentHeight,
                                child: Stack(
                                  children: <Widget>[
                                    Column(
                                      children: <Widget>[
                                        SizedBox(
                                          height: _rulerHeight,
                                          child: _TimelineRuler(
                                            width: contentWidth,
                                            duration: duration,
                                          ),
                                        ),
                                        for (final label in labels)
                                          _TimelineTrackLane(
                                            label: label,
                                            height: _trackHeight,
                                            contentWidth: contentWidth,
                                            durationUs: durationUs,
                                            clips: _clipsForTrack(label),
                                            selectedClipId: _selectedClipId,
                                            audioLane: label == 'A1',
                                            onClipTap: _selectClip,
                                            onEmptyTap: label == 'V1'
                                                ? widget.onImport
                                                : null,
                                          ),
                                      ],
                                    ),
                                    Positioned(
                                      left: playheadX - 0.75,
                                      top: _rulerHeight - 2,
                                      bottom: 0,
                                      child: IgnorePointer(
                                        child: Container(
                                          width: 1.5,
                                          color: _playheadColor,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: (playheadX - 13)
                                          .clamp(0.0, math.max(0.0, contentWidth - 26))
                                          .toDouble(),
                                      top: 0,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapDown: (details) => _seekFromGlobal(
                                          details.globalPosition,
                                          contentWidth,
                                        ),
                                        onHorizontalDragStart: (details) =>
                                            _seekFromGlobal(
                                          details.globalPosition,
                                          contentWidth,
                                        ),
                                        onHorizontalDragUpdate: (details) =>
                                            _seekFromGlobal(
                                          details.globalPosition,
                                          contentWidth,
                                        ),
                                        child: const SizedBox(
                                          width: 26,
                                          height: _rulerHeight,
                                          child: Center(
                                            child: Icon(
                                              Icons.arrow_drop_down,
                                              size: 24,
                                              color: _playheadColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
          const SizedBox(width: 6),
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
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.add, size: 18, color: Color(0xFFD9D9E0)),
            ),
          ),
          const Spacer(),
          Text(
            _formatDuration(position),
            style: const TextStyle(
              color: Color(0xFFB9B9C2),
              fontSize: 10,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          _ToolbarButton(
            icon: Icons.tune,
            label: 'Edit',
            onTap: onEdit,
          ),
          const SizedBox(width: 4),
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
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
  const _TrackHeader({
    required this.label,
    required this.height,
    required this.hasClip,
  });

  final String label;
  final double height;
  final bool hasClip;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
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
            color: hasClip
                ? const Color(0xFFE0E0E6)
                : const Color(0xFF777781),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _TimelineTrackLane extends StatelessWidget {
  const _TimelineTrackLane({
    required this.label,
    required this.height,
    required this.contentWidth,
    required this.durationUs,
    required this.clips,
    required this.selectedClipId,
    required this.audioLane,
    required this.onClipTap,
    required this.onEmptyTap,
  });

  final String label;
  final double height;
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
        height: height,
        decoration: const BoxDecoration(
          color: Color(0xFF101015),
          border: Border(bottom: BorderSide(color: Color(0xFF1C1C22))),
        ),
        child: Stack(
          children: <Widget>[
            for (final clip in clips)
              _clipWidget(clip),
          ],
        ),
      ),
    );
  }

  Widget _clipWidget(_TimelineClipView clip) {
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: audioLane
                ? const Color(0xFF28573D)
                : const Color(0xFF2D4772),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected && !audioLane
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF4B5D78),
              width: selected && !audioLane ? 1.5 : 0.6,
            ),
          ),
          child: Text(
            audioLane ? 'Audio · ${clip.title}' : clip.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFF2F2F5),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
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
    return Container(
      color: const Color(0xFF111116),
      child: Stack(
        children: <Widget>[
          for (int second = 0; second <= seconds; second += step)
            Positioned(
              left: second / seconds * width,
              top: 0,
              bottom: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(width: 1, height: 6, color: const Color(0xFF55555D)),
                  const SizedBox(height: 1),
                  Text(
                    _formatDuration(Duration(seconds: second)),
                    style: const TextStyle(
                      color: Color(0xFF777781),
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final totalMs = value.inMilliseconds.abs();
  final hours = totalMs ~/ 3600000;
  final minutes = (totalMs ~/ 60000) % 60;
  final seconds = (totalMs ~/ 1000) % 60;
  final millis = totalMs % 1000;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${(millis ~/ 10).toString().padLeft(2, '0')}';
}
