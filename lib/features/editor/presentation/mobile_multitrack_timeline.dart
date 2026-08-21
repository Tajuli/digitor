import 'package:flutter/material.dart';

import '../../../core/engine/engine_gateway.dart';

class MobileMultitrackTimeline extends StatefulWidget {
  const MobileMultitrackTimeline({
    super.key,
    required this.snapshot,
    required this.onImport,
    required this.onEdit,
    required this.onSeekUs,
    required this.onSelectClip,
    required this.onSplitSelected,
    required this.onDeleteSelected,
  });

  final EngineSnapshot snapshot;
  final VoidCallback onImport;
  final VoidCallback onEdit;
  final ValueChanged<int> onSeekUs;
  final ValueChanged<String> onSelectClip;
  final VoidCallback onSplitSelected;
  final VoidCallback onDeleteSelected;

  @override
  State<MobileMultitrackTimeline> createState() =>
      _MobileMultitrackTimelineState();
}

enum _TrackKind { video, audio }

final class _TimelineClipView {
  const _TimelineClipView({
    required this.id,
    required this.title,
    required this.timelineStartUs,
    required this.durationUs,
  });

  final String id;
  final String title;
  final int timelineStartUs;
  final int durationUs;

  int get timelineEndUs => timelineStartUs + durationUs;

  static _TimelineClipView? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString();
    final title = raw['displayName']?.toString();
    final start = raw['timelineStartUs'];
    final duration = raw['durationUs'];
    if (id == null ||
        id.isEmpty ||
        start is! num ||
        duration is! num ||
        duration.toInt() <= 0) {
      return null;
    }
    return _TimelineClipView(
      id: id,
      title: title == null || title.isEmpty ? 'Video' : title,
      timelineStartUs: start.toInt(),
      durationUs: duration.toInt(),
    );
  }
}

class _MobileMultitrackTimelineState extends State<MobileMultitrackTimeline> {
  static const double _trackHeaderWidth = 54;
  static const double _rulerHeight = 24;
  static const double _trackHeight = 34;
  static const double _pixelsPerSecond = 46;
  static const Color _playheadColor = Color(0xFFFF4D4D);
  static const int _maxTracksPerType = 32;

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  final GlobalKey _contentKey = GlobalKey();

  int _videoTrackCount = 1;
  int _audioTrackCount = 1;

  List<_TimelineClipView> get _clips {
    final raw = widget.snapshot.state['timelineClips'];
    if (raw is! List) return const <_TimelineClipView>[];
    return raw
        .map(_TimelineClipView.fromMap)
        .whereType<_TimelineClipView>()
        .toList(growable: false);
  }

  String? get _selectedClipId =>
      widget.snapshot.state['selectedClipId']?.toString();

  bool get _canSplitSelected =>
      widget.snapshot.state['canSplitSelected'] == true;

  List<String> get _trackLabels => <String>[
        for (int index = _videoTrackCount; index >= 1; index--) 'V$index',
        for (int index = 1; index <= _audioTrackCount; index++) 'A$index',
      ];

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _addTrack(_TrackKind kind) {
    setState(() {
      switch (kind) {
        case _TrackKind.video:
          if (_videoTrackCount < _maxTracksPerType) _videoTrackCount += 1;
          break;
        case _TrackKind.audio:
          if (_audioTrackCount < _maxTracksPerType) _audioTrackCount += 1;
          break;
      }
    });
  }

  void _seekAt(double x, double contentWidth) {
    final durationUs = widget.snapshot.duration.inMicroseconds;
    if (!widget.snapshot.connected || durationUs <= 0 || contentWidth <= 0) {
      return;
    }
    final fraction = (x / contentWidth).clamp(0.0, 1.0).toDouble();
    widget.onSeekUs((durationUs * fraction).round());
  }

  void _seekFromGlobal(Offset globalPosition, double contentWidth) {
    final renderObject = _contentKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    final local = renderObject.globalToLocal(globalPosition);
    _seekAt(local.dx, contentWidth);
  }

  @override
  Widget build(BuildContext context) {
    final labels = _trackLabels;
    final clips = _clips;
    final selectedClipId = _selectedClipId;
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
            position: widget.snapshot.position,
            onImport: widget.onImport,
            onEdit: widget.onEdit,
            onAddTrack: _addTrack,
            onSplit: _canSplitSelected ? widget.onSplitSelected : null,
            onDelete: selectedClipId == null ? null : widget.onDeleteSelected,
            canAddVideo: _videoTrackCount < _maxTracksPerType,
            canAddAudio: _audioTrackCount < _maxTracksPerType,
            clipCount: clips.length,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final rawViewportWidth =
                    constraints.maxWidth - _trackHeaderWidth;
                final viewportWidth = rawViewportWidth > 1
                    ? rawViewportWidth
                    : 1.0;
                final seconds =
                    widget.snapshot.duration.inMilliseconds / 1000.0;
                final requestedWidth = seconds <= 0
                    ? viewportWidth * 1.6
                    : seconds * _pixelsPerSecond;
                final contentWidth = requestedWidth
                    .clamp(viewportWidth, 8000.0)
                    .toDouble();
                final durationUs = widget.snapshot.duration.inMicroseconds;
                final positionUs = widget.snapshot.position.inMicroseconds;
                final positionFraction = durationUs <= 0
                    ? 0.0
                    : (positionUs / durationUs).clamp(0.0, 1.0).toDouble();
                final playheadX = positionFraction * contentWidth;
                final playheadHeaderMax =
                    contentWidth > 26 ? contentWidth - 26 : 0.0;
                final playheadHeaderLeft =
                    (playheadX - 13).clamp(0.0, playheadHeaderMax).toDouble();
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
                                const _TimelineCorner(),
                                for (final label in labels)
                                  _TrackHeader(
                                    label: label,
                                    height: _trackHeight,
                                    hasClip: clips.isNotEmpty &&
                                        (label == 'V1' || label == 'A1'),
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
                                  clipBehavior: Clip.none,
                                  children: <Widget>[
                                    Column(
                                      children: <Widget>[
                                        SizedBox(
                                          height: _rulerHeight,
                                          child: _TimelineRuler(
                                            width: contentWidth,
                                            duration: widget.snapshot.duration,
                                          ),
                                        ),
                                        for (final label in labels)
                                          _TimelineTrackLane(
                                            label: label,
                                            height: _trackHeight,
                                            contentWidth: contentWidth,
                                            timelineDurationUs: durationUs,
                                            isVideo: label.startsWith('V'),
                                            clips: label == 'V1' || label == 'A1'
                                                ? clips
                                                : const <_TimelineClipView>[],
                                            selectedClipId: selectedClipId,
                                            onClipTap: widget.onSelectClip,
                                            onEmptyTap: clips.isEmpty && label == 'V1'
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
                                      left: playheadHeaderLeft,
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
                                          child: Center(child: _PlayheadHeader()),
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
    required this.clipCount,
  });

  final Duration position;
  final VoidCallback onImport;
  final VoidCallback onEdit;
  final ValueChanged<_TrackKind> onAddTrack;
  final VoidCallback? onSplit;
  final VoidCallback? onDelete;
  final bool canAddVideo;
  final bool canAddAudio;
  final int clipCount;

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.only(left: 7, right: 3),
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E12),
          border: Border(bottom: BorderSide(color: Color(0xFF24242A))),
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.view_timeline_outlined,
              size: 13,
              color: Colors.white54,
            ),
            const SizedBox(width: 4),
            Text(
              clipCount == 0 ? 'Timeline' : '$clipCount clip${clipCount == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                color: Colors.white60,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF17171C),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _timelineClock(position),
                style: const TextStyle(fontSize: 7.5, color: Colors.white54),
              ),
            ),
            const Spacer(),
            PopupMenuButton<_TrackKind>(
              tooltip: 'Add track',
              enabled: canAddVideo || canAddAudio,
              onSelected: onAddTrack,
              itemBuilder: (context) => <PopupMenuEntry<_TrackKind>>[
                PopupMenuItem<_TrackKind>(
                  value: _TrackKind.video,
                  enabled: canAddVideo,
                  child: const Row(
                    children: <Widget>[
                      Icon(Icons.videocam_outlined, size: 17),
                      SizedBox(width: 8),
                      Text('Add video track'),
                    ],
                  ),
                ),
                PopupMenuItem<_TrackKind>(
                  value: _TrackKind.audio,
                  enabled: canAddAudio,
                  child: const Row(
                    children: <Widget>[
                      Icon(Icons.volume_up_outlined, size: 17),
                      SizedBox(width: 8),
                      Text('Add audio track'),
                    ],
                  ),
                ),
              ],
              child: _ToolbarChip(
                icon: Icons.add_rounded,
                label: 'Track',
                enabled: canAddVideo || canAddAudio,
              ),
            ),
            const SizedBox(width: 2),
            InkWell(
              onTap: onImport,
              borderRadius: BorderRadius.circular(5),
              child: const _ToolbarChip(
                icon: Icons.video_call_outlined,
                label: 'Video',
                enabled: true,
              ),
            ),
            IconButton(
              tooltip: 'Split selected clip at playhead',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 27, height: 28),
              onPressed: onSplit,
              icon: const Icon(Icons.content_cut_rounded, size: 15),
            ),
            IconButton(
              tooltip: 'Delete selected clip',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 27, height: 28),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
            ),
            IconButton(
              tooltip: 'Edit tools',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 27, height: 28),
              onPressed: onEdit,
              icon: const Icon(Icons.tune_rounded, size: 15),
            ),
          ],
        ),
      );
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF17171C),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 13,
              color: enabled ? Colors.white70 : Colors.white24,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 7.5,
                color: enabled ? Colors.white70 : Colors.white24,
              ),
            ),
          ],
        ),
      );
}

class _TimelineCorner extends StatelessWidget {
  const _TimelineCorner();

  @override
  Widget build(BuildContext context) => Container(
        height: _MobileMultitrackTimelineState._rulerHeight,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFF111116),
          border: Border(
            right: BorderSide(color: Color(0xFF2B2B31)),
            bottom: BorderSide(color: Color(0xFF2B2B31)),
          ),
        ),
        child: const Text(
          'TC',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
          ),
        ),
      );
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

  bool get _isVideo => label.startsWith('V');

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: hasClip ? const Color(0xFF18181E) : const Color(0xFF121217),
          border: Border(
            right: const BorderSide(color: Color(0xFF2B2B31)),
            bottom: const BorderSide(color: Color(0xFF24242A)),
            top: label == 'A1'
                ? const BorderSide(color: Color(0xFF3A3A42))
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 3,
              height: double.infinity,
              color: hasClip
                  ? (_isVideo
                      ? const Color(0xFF607D9B)
                      : const Color(0xFF3E7569))
                  : Colors.transparent,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: hasClip ? Colors.white70 : Colors.white38,
              ),
            ),
            const Spacer(),
            Icon(
              _isVideo ? Icons.videocam_outlined : Icons.volume_up_outlined,
              size: 11,
              color: hasClip ? Colors.white38 : Colors.white24,
            ),
            const SizedBox(width: 5),
          ],
        ),
      );
}

class _TimelineRuler extends StatelessWidget {
  const _TimelineRuler({required this.width, required this.duration});

  final double width;
  final Duration duration;

  double get _totalSeconds {
    final seconds = duration.inMilliseconds / 1000.0;
    return seconds > 0 ? seconds : 15;
  }

  double get _majorStep {
    final seconds = _totalSeconds;
    if (seconds <= 30) return 5;
    if (seconds <= 120) return 10;
    if (seconds <= 600) return 30;
    if (seconds <= 3600) return 60;
    return 300;
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalSeconds;
    final step = _majorStep;
    final labelMaxX = width > 34 ? width - 34 : 0.0;
    final ticks = <Widget>[];
    for (double second = 0; second <= total; second += step) {
      final x = (second / total) * width;
      ticks.add(
        Positioned(
          left: x.clamp(0.0, labelMaxX).toDouble(),
          top: 0,
          bottom: 0,
          child: SizedBox(
            width: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(width: 1, height: 7, color: Colors.white30),
                const SizedBox(height: 1),
                Text(
                  _rulerClock(second.round()),
                  style: const TextStyle(fontSize: 7, color: Colors.white38),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF111116),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2B2B31))),
              ),
            ),
          ),
          ...ticks,
        ],
      ),
    );
  }
}

class _TimelineTrackLane extends StatelessWidget {
  const _TimelineTrackLane({
    required this.label,
    required this.height,
    required this.contentWidth,
    required this.timelineDurationUs,
    required this.isVideo,
    required this.clips,
    required this.selectedClipId,
    required this.onClipTap,
    this.onEmptyTap,
  });

  final String label;
  final double height;
  final double contentWidth;
  final int timelineDurationUs;
  final bool isVideo;
  final List<_TimelineClipView> clips;
  final String? selectedClipId;
  final ValueChanged<String> onClipTap;
  final VoidCallback? onEmptyTap;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: label == 'V1' || label == 'A1'
              ? const Color(0xFF101016)
              : const Color(0xFF0D0D12),
          border: Border(
            bottom: const BorderSide(color: Color(0xFF24242A)),
            top: label == 'A1'
                ? const BorderSide(color: Color(0xFF3A3A42))
                : BorderSide.none,
          ),
        ),
        child: Stack(
          children: <Widget>[
            for (final clip in clips)
              _positionedClip(context, clip),
            if (clips.isEmpty && onEmptyTap != null)
              Positioned(
                left: 5,
                top: 3,
                bottom: 3,
                child: InkWell(
                  onTap: onEmptyTap,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: (contentWidth * 0.36).clamp(120.0, 220.0).toDouble(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF17171D),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      children: <Widget>[
                        Icon(Icons.add_rounded, size: 13, color: Colors.white54),
                        SizedBox(width: 5),
                        Text(
                          'Add video',
                          style: TextStyle(fontSize: 8, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _positionedClip(BuildContext context, _TimelineClipView clip) {
    final totalUs = timelineDurationUs <= 0 ? 1 : timelineDurationUs;
    final left = (clip.timelineStartUs / totalUs) * contentWidth;
    final naturalWidth = (clip.durationUs / totalUs) * contentWidth;
    final available = (contentWidth - left).clamp(1.0, contentWidth).toDouble();
    final width = naturalWidth.clamp(12.0, available).toDouble();
    return Positioned(
      left: left,
      width: width,
      top: 3,
      bottom: 3,
      child: Padding(
        padding: const EdgeInsets.only(right: 2),
        child: _TrackClip(
          title: clip.title,
          duration: Duration(microseconds: clip.durationUs),
          isVideo: isVideo,
          selected: selectedClipId == clip.id,
          onTap: () => onClipTap(clip.id),
        ),
      ),
    );
  }
}

class _TrackClip extends StatelessWidget {
  const _TrackClip({
    required this.title,
    required this.duration,
    required this.isVideo,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final Duration duration;
  final bool isVideo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isVideo ? const Color(0xFF27313C) : const Color(0xFF173B34),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              width: selected ? 2 : 1,
              color: selected
                  ? selectedColor
                  : isVideo
                      ? const Color(0xFF52677C)
                      : const Color(0xFF35685E),
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Opacity(
                  opacity: 0.24,
                  child: CustomPaint(
                    painter: _ClipPatternPainter(isVideo: isVideo),
                  ),
                ),
              ),
              Positioned(
                left: 5,
                right: 4,
                bottom: 2,
                child: Row(
                  children: <Widget>[
                    Icon(
                      isVideo ? Icons.movie_outlined : Icons.graphic_eq_rounded,
                      size: 9,
                      color: Colors.white60,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 7.2,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    if (duration.inMilliseconds >= 800) ...<Widget>[
                      const SizedBox(width: 3),
                      Text(
                        _durationLabel(duration),
                        style: const TextStyle(
                          fontSize: 6.8,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  top: 2,
                  right: 3,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: selectedColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClipPatternPainter extends CustomPainter {
  const _ClipPatternPainter({required this.isVideo});

  final bool isVideo;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;
    if (isVideo) {
      for (double x = 3; x < size.width; x += 12) {
        canvas.drawLine(Offset(x, 3), Offset(x + 7, size.height - 3), paint);
      }
    } else {
      final center = size.height * 0.5;
      for (double x = 2; x < size.width; x += 4) {
        final amplitude = ((x.toInt() ~/ 4) % 3 + 1) * 2.0;
        canvas.drawLine(
          Offset(x, center - amplitude),
          Offset(x, center + amplitude),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ClipPatternPainter oldDelegate) =>
      oldDelegate.isVideo != isVideo;
}

class _PlayheadHeader extends StatelessWidget {
  const _PlayheadHeader();

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(12, 13),
        painter: _PlayheadHeaderPainter(),
      );
}

class _PlayheadHeaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(1, 1)
      ..lineTo(size.width - 1, 1)
      ..lineTo(size.width - 1, size.height * 0.58)
      ..lineTo(size.width * 0.5, size.height - 1)
      ..lineTo(1, size.height * 0.58)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFF4D4D));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _timelineClock(Duration value) {
  final totalMs = value.inMilliseconds.clamp(0, 1 << 62);
  final minutes = totalMs ~/ 60000;
  final seconds = (totalMs ~/ 1000) % 60;
  final millis = totalMs % 1000;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}

String _rulerClock(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _durationLabel(Duration value) {
  final totalSeconds = value.inMilliseconds / 1000.0;
  if (totalSeconds < 60) return '${totalSeconds.toStringAsFixed(1)}s';
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).round();
  return '${minutes}m ${seconds}s';
}
