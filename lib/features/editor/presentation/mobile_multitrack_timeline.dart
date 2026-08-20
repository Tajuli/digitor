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

class _MobileMultitrackTimelineState extends State<MobileMultitrackTimeline> {
  static const double _trackHeaderWidth = 54;
  static const double _rulerHeight = 24;
  static const double _pixelsPerSecond = 46;
  static const Color _playheadColor = Color(0xFFFF4D4D);
  static const List<String> _trackLabels = <String>[
    'V3',
    'V2',
    'V1',
    'A1',
    'A2',
    'A3',
  ];

  final ScrollController _horizontalController = ScrollController();
  final GlobalKey _contentKey = GlobalKey();

  String? get _mediaPath => widget.snapshot.state['mediaPath']?.toString();

  String get _mediaName {
    final path = _mediaPath;
    if (path == null || path.isEmpty) return 'No media';
    return path.replaceAll('\\', '/').split('/').last;
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
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
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewportWidth =
                    (constraints.maxWidth - _trackHeaderWidth)
                        .clamp(1.0, double.infinity)
                        .toDouble();
                final seconds = widget.snapshot.duration.inMilliseconds / 1000.0;
                final requestedWidth = seconds <= 0
                    ? viewportWidth * 1.6
                    : seconds * _pixelsPerSecond;
                final contentWidth = requestedWidth
                    .clamp(viewportWidth, 8000.0)
                    .toDouble();
                final availableForTracks =
                    (constraints.maxHeight - _rulerHeight)
                        .clamp(0.0, double.infinity)
                        .toDouble();
                final trackHeight =
                    (availableForTracks / _trackLabels.length)
                        .clamp(20.0, 32.0)
                        .toDouble();
                final durationUs = widget.snapshot.duration.inMicroseconds;
                final positionUs = widget.snapshot.position.inMicroseconds;
                final positionFraction = durationUs <= 0
                    ? 0.0
                    : (positionUs / durationUs).clamp(0.0, 1.0).toDouble();
                final playheadX = positionFraction * contentWidth;

                return Row(
                  children: <Widget>[
                    SizedBox(
                      width: _trackHeaderWidth,
                      child: Column(
                        children: <Widget>[
                          Container(
                            height: _rulerHeight,
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
                          ),
                          for (final label in _trackLabels)
                            _TrackHeader(
                              label: label,
                              height: trackHeight,
                              active: label == 'V1' || label == 'A1',
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
                          height: constraints.maxHeight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTapDown: (details) =>
                                _seekAt(details.localPosition.dx, contentWidth),
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
                                    _TimelineTrackLane(
                                      label: 'V3',
                                      height: trackHeight,
                                      contentWidth: contentWidth,
                                      isVideo: true,
                                    ),
                                    _TimelineTrackLane(
                                      label: 'V2',
                                      height: trackHeight,
                                      contentWidth: contentWidth,
                                      isVideo: true,
                                    ),
                                    _TimelineTrackLane(
                                      label: 'V1',
                                      height: trackHeight,
                                      contentWidth: contentWidth,
                                      isVideo: true,
                                      clipTitle: _mediaPath == null ? null : _mediaName,
                                      duration: widget.snapshot.duration,
                                      onEmptyTap: _mediaPath == null
                                          ? widget.onImport
                                          : null,
                                    ),
                                    _TimelineTrackLane(
                                      label: 'A1',
                                      height: trackHeight,
                                      contentWidth: contentWidth,
                                      isVideo: false,
                                      clipTitle: _mediaPath == null ? null : _mediaName,
                                      duration: widget.snapshot.duration,
                                    ),
                                    _TimelineTrackLane(
                                      label: 'A2',
                                      height: trackHeight,
                                      contentWidth: contentWidth,
                                      isVideo: false,
                                    ),
                                    _TimelineTrackLane(
                                      label: 'A3',
                                      height: trackHeight,
                                      contentWidth: contentWidth,
                                      isVideo: false,
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
                                      .clamp(0.0, contentWidth - 26)
                                      .toDouble(),
                                  top: 0,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
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
                                      height: 25,
                                      child: Center(
                                        child: _PlayheadHeader(),
                                      ),
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
  });

  final Duration position;
  final VoidCallback onImport;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Container(
        height: 28,
        padding: const EdgeInsets.only(left: 9, right: 3),
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
            const SizedBox(width: 5),
            const Text(
              'Timeline',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white60,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF17171C),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _timelineClock(position),
                style: const TextStyle(
                  fontSize: 8,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  color: Colors.white54,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Import media',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded, size: 17),
            ),
            TextButton.icon(
              onPressed: onEdit,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 5),
              ),
              icon: const Icon(Icons.content_cut_rounded, size: 12),
              label: const Text('Edit', style: TextStyle(fontSize: 8)),
            ),
          ],
        ),
      );
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({
    required this.label,
    required this.height,
    required this.active,
  });

  final String label;
  final double height;
  final bool active;

  bool get _isVideo => label.startsWith('V');

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF18181E) : const Color(0xFF121217),
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
              color: active
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
                color: active ? Colors.white70 : Colors.white38,
              ),
            ),
            const Spacer(),
            Icon(
              _isVideo ? Icons.videocam_outlined : Icons.volume_up_outlined,
              size: 11,
              color: active ? Colors.white38 : Colors.white24,
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
    final ticks = <Widget>[];
    for (double second = 0; second <= total; second += step) {
      final x = (second / total) * width;
      ticks.add(
        Positioned(
          left: x.clamp(0.0, width - 34).toDouble(),
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
    required this.isVideo,
    this.clipTitle,
    this.duration = Duration.zero,
    this.onEmptyTap,
  });

  final String label;
  final double height;
  final double contentWidth;
  final bool isVideo;
  final String? clipTitle;
  final Duration duration;
  final VoidCallback? onEmptyTap;

  @override
  Widget build(BuildContext context) {
    final hasClip = clipTitle != null && clipTitle!.isNotEmpty;
    return Container(
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
          if (hasClip)
            Positioned(
              left: 4,
              right: 4,
              top: 3,
              bottom: 3,
              child: _TrackClip(
                title: clipTitle!,
                duration: duration,
                isVideo: isVideo,
              ),
            )
          else if (onEmptyTap != null)
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
                        'Add media',
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
  }
}

class _TrackClip extends StatelessWidget {
  const _TrackClip({
    required this.title,
    required this.duration,
    required this.isVideo,
  });

  final String title;
  final Duration duration;
  final bool isVideo;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isVideo ? const Color(0xFF27313C) : const Color(0xFF173B34),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isVideo ? const Color(0xFF52677C) : const Color(0xFF35685E),
          ),
        ),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Opacity(
                opacity: 0.28,
                child: isVideo ? const _VideoPattern() : const _AudioPattern(),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 2,
              child: Row(
                children: <Widget>[
                  Icon(
                    isVideo ? Icons.movie_outlined : Icons.graphic_eq_rounded,
                    size: 10,
                    color: Colors.white60,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 7.5, color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _durationLabel(duration),
                    style: const TextStyle(fontSize: 7, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _VideoPattern extends StatelessWidget {
  const _VideoPattern();

  @override
  Widget build(BuildContext context) => Row(
        children: List<Widget>.generate(
          14,
          (index) => Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: index == 13 ? Colors.transparent : Colors.white24,
                  ),
                ),
              ),
              child: const Icon(
                Icons.movie_outlined,
                size: 11,
                color: Colors.white30,
              ),
            ),
          ),
        ),
      );
}

class _AudioPattern extends StatelessWidget {
  const _AudioPattern();

  static const List<double> _heights = <double>[
    0.25,
    0.55,
    0.8,
    0.42,
    0.7,
    0.34,
    0.9,
    0.48,
    0.72,
    0.3,
    0.6,
    0.84,
    0.4,
    0.68,
    0.36,
    0.76,
  ];

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (final height in _heights)
            Expanded(
              child: FractionallySizedBox(
                heightFactor: height,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  color: Colors.white38,
                ),
              ),
            ),
        ],
      );
}

class _PlayheadHeader extends StatelessWidget {
  const _PlayheadHeader();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 15,
            height: 10,
            decoration: const BoxDecoration(
              color: _MobileMultitrackTimelineState._playheadColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(2),
                topRight: Radius.circular(2),
              ),
            ),
          ),
          ClipPath(
            clipper: _DownTriangleClipper(),
            child: Container(
              width: 15,
              height: 7,
              color: _MobileMultitrackTimelineState._playheadColor,
            ),
          ),
        ],
      );
}

class _DownTriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width / 2, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

String _timelineClock(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);
  final centiseconds = value.inMilliseconds.remainder(1000) ~/ 10;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${centiseconds.toString().padLeft(2, '0')}';
}

String _rulerClock(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainder.toString().padLeft(2, '0')}';
}

String _durationLabel(Duration value) {
  if (value.inMilliseconds <= 0) return '--';
  if (value.inSeconds < 1) return '<1s';
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60);
  return minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
}
