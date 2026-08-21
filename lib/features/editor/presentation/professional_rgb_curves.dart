import 'dart:async';

import 'package:flutter/material.dart';

class ProfessionalRgbCurvesControls extends StatefulWidget {
  const ProfessionalRgbCurvesControls({
    super.key,
    required this.supported,
    required this.dispatch,
  });

  final bool supported;
  final Future<void> Function(String, String, [Object?]) dispatch;

  @override
  State<ProfessionalRgbCurvesControls> createState() =>
      _ProfessionalRgbCurvesControlsState();
}

class _ProfessionalRgbCurvesControlsState
    extends State<ProfessionalRgbCurvesControls> {
  static const List<String> _channels = <String>[
    'master',
    'red',
    'green',
    'blue',
  ];
  static const double _edgePadding = 14;
  static const double _hitRadius = 22;
  static const double _xGap = 0.002;
  static const double _graphWidthFactor = 0.78;
  static const double _minGraphWidth = 180;
  static const double _maxGraphWidth = 320;

  final Map<String, List<_CurvePoint>> _points = <String, List<_CurvePoint>>{
    for (final channel in _channels)
      channel: <_CurvePoint>[
        const _CurvePoint(0, 0),
        const _CurvePoint(1, 1),
      ],
  };

  final GlobalKey _graphKey = GlobalKey();
  String _channel = 'master';
  int? _selectedIndex;
  int? _activePointer;
  Timer? _dispatchTimer;
  bool _dispatchPending = false;

  List<_CurvePoint> get _activePoints => _points[_channel]!;

  @override
  void dispose() {
    _dispatchTimer?.cancel();
    super.dispose();
  }

  Color _channelColor(BuildContext context, String channel) {
    switch (channel) {
      case 'red':
        return Colors.redAccent;
      case 'green':
        return Colors.greenAccent;
      case 'blue':
        return Colors.lightBlueAccent;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _channelLabel(String channel) {
    switch (channel) {
      case 'red':
        return 'R';
      case 'green':
        return 'G';
      case 'blue':
        return 'B';
      default:
        return 'Y';
    }
  }

  Rect _graphRect(Size size) {
    final width = (size.width - (_edgePadding * 2))
        .clamp(1.0, double.infinity)
        .toDouble();
    final height = (size.height - (_edgePadding * 2))
        .clamp(1.0, double.infinity)
        .toDouble();
    return Rect.fromLTWH(_edgePadding, _edgePadding, width, height);
  }

  Offset _pointToOffset(_CurvePoint point, Rect rect) => Offset(
        rect.left + point.x * rect.width,
        rect.bottom - point.y * rect.height,
      );

  _CurvePoint _offsetToPoint(Offset position, Rect rect) {
    final x = ((position.dx - rect.left) / rect.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final y = (1 - ((position.dy - rect.top) / rect.height))
        .clamp(0.0, 1.0)
        .toDouble();
    return _CurvePoint(x, y);
  }

  int? _nearestPoint(Offset position, Rect rect) {
    final points = _activePoints;
    var nearestDistance = double.infinity;
    int? nearest;
    for (var index = 0; index < points.length; index++) {
      final distance = (_pointToOffset(points[index], rect) - position).distance;
      if (distance <= _hitRadius && distance < nearestDistance) {
        nearestDistance = distance;
        nearest = index;
      }
    }
    return nearest;
  }

  int? _insertPoint(_CurvePoint point) {
    final points = _activePoints;
    final insertAt = points.indexWhere((item) => item.x > point.x);

    if (insertAt == 0) {
      final maxX = points.first.x - _xGap;
      if (maxX < 0) return null;
      points.insert(
        0,
        _CurvePoint(point.x.clamp(0.0, maxX).toDouble(), point.y),
      );
      return 0;
    }

    if (insertAt < 0) {
      final minX = points.last.x + _xGap;
      if (minX > 1) return null;
      points.add(
        _CurvePoint(point.x.clamp(minX, 1.0).toDouble(), point.y),
      );
      return points.length - 1;
    }

    final minX = points[insertAt - 1].x + _xGap;
    final maxX = points[insertAt].x - _xGap;
    if (minX > maxX) return null;
    points.insert(
      insertAt,
      _CurvePoint(point.x.clamp(minX, maxX).toDouble(), point.y),
    );
    return insertAt;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.supported || _activePointer != null) return;
    final renderObject = _graphKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    final rect = _graphRect(renderObject.size);
    final local = event.localPosition;
    var selected = _nearestPoint(local, rect);

    setState(() {
      _activePointer = event.pointer;
      selected ??= _insertPoint(_offsetToPoint(local, rect));
      _selectedIndex = selected;
    });

    if (selected != null) {
      _updateSelected(local, rect, scheduleDispatch: true);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _selectedIndex == null) return;
    final renderObject = _graphKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    _updateSelected(event.localPosition, _graphRect(renderObject.size));
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _flushDispatch();
  }

  void _updateSelected(
    Offset position,
    Rect rect, {
    bool scheduleDispatch = true,
  }) {
    final index = _selectedIndex;
    if (index == null) return;
    final points = _activePoints;
    if (index < 0 || index >= points.length) return;
    final incoming = _offsetToPoint(position, rect);

    final minX = index == 0 ? 0.0 : points[index - 1].x + _xGap;
    final maxX = index == points.length - 1
        ? 1.0
        : points[index + 1].x - _xGap;
    final x = incoming.x.clamp(minX, maxX).toDouble();

    setState(() {
      points[index] = _CurvePoint(x, incoming.y);
    });
    if (scheduleDispatch) _scheduleDispatch();
  }

  void _scheduleDispatch() {
    if (!widget.supported) return;
    _dispatchPending = true;
    if (_dispatchTimer?.isActive ?? false) return;
    _dispatchTimer = Timer(const Duration(milliseconds: 24), _flushDispatch);
  }

  List<Map<String, double>> _enginePoints() {
    final visible = _activePoints;
    final output = <Map<String, double>>[];
    final first = visible.first;
    final last = visible.last;

    if (first.x > 0) {
      output.add(<String, double>{'x': 0, 'y': first.y});
    }
    for (final point in visible) {
      output.add(<String, double>{'x': point.x, 'y': point.y});
    }
    if (last.x < 1) {
      output.add(<String, double>{'x': 1, 'y': last.y});
    }
    return output;
  }

  void _flushDispatch() {
    _dispatchTimer?.cancel();
    _dispatchTimer = null;
    if (!_dispatchPending || !widget.supported) return;
    _dispatchPending = false;
    final payload = <String, Object?>{
      'channel': _channel,
      'points': _enginePoints(),
    };
    unawaited(widget.dispatch('color.rgbCurves', 'points', payload));
  }

  void _selectChannel(String channel) {
    if (_channel == channel) return;
    _flushDispatch();
    setState(() {
      _channel = channel;
      _selectedIndex = null;
      _activePointer = null;
    });
    if (widget.supported) {
      unawaited(widget.dispatch('color.rgbCurves', 'channel', channel));
    }
  }

  void _deleteSelected() {
    final index = _selectedIndex;
    final points = _activePoints;
    if (index == null || points.length <= 2) return;
    if (index < 0 || index >= points.length) return;

    setState(() {
      points.removeAt(index);
      _selectedIndex = null;
      _activePointer = null;
    });
    _dispatchPending = true;
    _flushDispatch();
  }

  void _reset() {
    _dispatchTimer?.cancel();
    _dispatchTimer = null;
    _dispatchPending = false;
    setState(() {
      for (final channel in _channels) {
        _points[channel] = <_CurvePoint>[
          const _CurvePoint(0, 0),
          const _CurvePoint(1, 1),
        ];
      }
      _selectedIndex = null;
      _activePointer = null;
    });
    if (widget.supported) {
      unawaited(widget.dispatch('color.rgbCurves', 'reset'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _channelColor(context, _channel);
    final selectedIndex = _selectedIndex;
    final selectedPoint = selectedIndex == null ||
            selectedIndex < 0 ||
            selectedIndex >= _activePoints.length
        ? null
        : _activePoints[selectedIndex];
    final canDelete = selectedIndex != null && _activePoints.length > 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 30,
            child: Row(
              children: <Widget>[
                for (final channel in _channels) ...<Widget>[
                  Expanded(
                    child: _CurveChannelButton(
                      label: _channelLabel(channel),
                      selected: channel == _channel,
                      color: _channelColor(context, channel),
                      onPressed: widget.supported
                          ? () => _selectChannel(channel)
                          : null,
                    ),
                  ),
                  if (channel != _channels.last) const SizedBox(width: 4),
                ],
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Reset RGB curves',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.supported ? _reset : null,
                  icon: const Icon(Icons.restart_alt_rounded, size: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final graphWidth = (constraints.maxWidth * _graphWidthFactor)
                    .clamp(
                      constraints.maxWidth < _minGraphWidth
                          ? constraints.maxWidth
                          : _minGraphWidth,
                      constraints.maxWidth < _maxGraphWidth
                          ? constraints.maxWidth
                          : _maxGraphWidth,
                    )
                    .toDouble();
                return Center(
                  child: SizedBox(
                    width: graphWidth,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Listener(
                        key: _graphKey,
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: _onPointerDown,
                        onPointerMove: _onPointerMove,
                        onPointerUp: _onPointerUp,
                        onPointerCancel: _onPointerUp,
                        child: CustomPaint(
                          painter: _RgbCurvePainter(
                            points:
                                List<_CurvePoint>.unmodifiable(_activePoints),
                            selectedIndex: _selectedIndex,
                            curveColor: accent,
                            enabled: widget.supported,
                            edgePadding: _edgePadding,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 26,
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.touch_app_outlined,
                  size: 13,
                  color: Colors.white38,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    selectedPoint == null
                        ? 'Tap empty graph to add · drag every point in X/Y'
                        : 'Input ${(selectedPoint.x * 100).round()}  ·  Output ${(selectedPoint.y * 100).round()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 8.5, color: Colors.white54),
                  ),
                ),
                IconButton(
                  tooltip: canDelete
                      ? 'Delete selected point'
                      : 'Keep at least two curve points',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 30, height: 26),
                  onPressed:
                      widget.supported && canDelete ? _deleteSelected : null,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CurveChannelButton extends StatelessWidget {
  const _CurveChannelButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color:
            selected ? color.withValues(alpha: 0.14) : const Color(0xFF17171C),
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: onPressed,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: selected
                    ? color.withValues(alpha: 0.75)
                    : Colors.white12,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected ? color : Colors.white60,
              ),
            ),
          ),
        ),
      );
}

class _RgbCurvePainter extends CustomPainter {
  const _RgbCurvePainter({
    required this.points,
    required this.selectedIndex,
    required this.curveColor,
    required this.enabled,
    required this.edgePadding,
  });

  final List<_CurvePoint> points;
  final int? selectedIndex;
  final Color curveColor;
  final bool enabled;
  final double edgePadding;

  Rect _rect(Size size) {
    final width = (size.width - edgePadding * 2)
        .clamp(1.0, double.infinity)
        .toDouble();
    final height = (size.height - edgePadding * 2)
        .clamp(1.0, double.infinity)
        .toDouble();
    return Rect.fromLTWH(edgePadding, edgePadding, width, height);
  }

  Offset _offset(_CurvePoint point, Rect rect) => Offset(
        rect.left + point.x * rect.width,
        rect.bottom - point.y * rect.height,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _rect(size);
    canvas.drawRect(
      rect.inflate(edgePadding),
      Paint()..color = const Color(0xFF0A0A0E),
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final t = index / 4;
      final x = rect.left + rect.width * t;
      final y = rect.top + rect.height * t;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }

    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.right, rect.top),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..strokeWidth = 1,
    );

    if (points.length >= 2) {
      final mapped = <Offset>[for (final point in points) _offset(point, rect)];
      final path = Path()..moveTo(mapped.first.dx, mapped.first.dy);
      for (var index = 0; index < mapped.length - 1; index++) {
        final a = mapped[index];
        final b = mapped[index + 1];
        final dx = b.dx - a.dx;
        path.cubicTo(
          a.dx + dx * 0.38,
          a.dy,
          b.dx - dx * 0.38,
          b.dy,
          b.dx,
          b.dy,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = enabled ? curveColor : Colors.white30
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      for (var index = 0; index < mapped.length; index++) {
        final selected = index == selectedIndex;
        final center = mapped[index];
        if (selected) {
          canvas.drawCircle(
            center,
            9,
            Paint()..color = curveColor.withValues(alpha: 0.17),
          );
        }
        canvas.drawCircle(
          center,
          selected ? 5.5 : 4.2,
          Paint()..color = const Color(0xFF0A0A0E),
        );
        canvas.drawCircle(
          center,
          selected ? 5.5 : 4.2,
          Paint()
            ..color = enabled ? curveColor : Colors.white38
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 2.2 : 1.6,
        );
      }
    }

    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _RgbCurvePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.curveColor != curveColor ||
      oldDelegate.enabled != enabled;
}

class _CurvePoint {
  const _CurvePoint(this.x, this.y);

  final double x;
  final double y;
}
