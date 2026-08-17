import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

typedef ColorWheelDispatch = Future<void> Function(
  String feature,
  String control, [
  Object? value,
]);

class ProfessionalPrimaryWheelsControls extends StatefulWidget {
  const ProfessionalPrimaryWheelsControls({
    super.key,
    required this.supported,
    required this.dispatch,
  });

  final bool supported;
  final ColorWheelDispatch dispatch;

  @override
  State<ProfessionalPrimaryWheelsControls> createState() =>
      _ProfessionalPrimaryWheelsControlsState();
}

class _ProfessionalPrimaryWheelsControlsState
    extends State<ProfessionalPrimaryWheelsControls> {
  static const _specs = <_PrimaryWheelSpec>[
    _PrimaryWheelSpec(
      title: 'Lift',
      keyName: 'lift',
      identityRgb: 0,
      identityMaster: 0,
      masterMin: -4,
      masterMax: 4,
      colorScale: 1.35,
    ),
    _PrimaryWheelSpec(
      title: 'Gamma',
      keyName: 'gamma',
      identityRgb: 1,
      identityMaster: 1,
      masterMin: 0.01,
      masterMax: 10,
      colorScale: 0.80,
    ),
    _PrimaryWheelSpec(
      title: 'Gain',
      keyName: 'gain',
      identityRgb: 1,
      identityMaster: 1,
      masterMin: 0,
      masterMax: 16,
      colorScale: 1.35,
    ),
    _PrimaryWheelSpec(
      title: 'Offset',
      keyName: 'offset',
      identityRgb: 0,
      identityMaster: 0,
      masterMin: -4,
      masterMax: 4,
      colorScale: 0.80,
    ),
  ];

  final _pucks = <String, Offset>{
    for (final spec in _specs) spec.keyName: Offset.zero,
  };
  final _values = <String, double>{
    for (final spec in _specs) ...<String, double>{
      '${spec.keyName}R': spec.identityRgb,
      '${spec.keyName}G': spec.identityRgb,
      '${spec.keyName}B': spec.identityRgb,
      '${spec.keyName}Master': spec.identityMaster,
    },
  };

  double _value(String key) => _values[key] ?? 0;

  Future<void> _commitWheel(_PrimaryWheelSpec spec) => widget.dispatch(
        'color.primaryWheels',
        'setWheel',
        <String, Object?>{
          'name': spec.keyName,
          'r': _value('${spec.keyName}R'),
          'g': _value('${spec.keyName}G'),
          'b': _value('${spec.keyName}B'),
          'master': _value('${spec.keyName}Master'),
        },
      );

  void _setPuck(_PrimaryWheelSpec spec, Offset puck) {
    final delta = _chromaticDelta(puck);
    setState(() {
      _pucks[spec.keyName] = puck;
      _values['${spec.keyName}R'] =
          (spec.identityRgb + delta.$1 * spec.colorScale)
              .clamp(spec.rgbMin, spec.rgbMax)
              .toDouble();
      _values['${spec.keyName}G'] =
          (spec.identityRgb + delta.$2 * spec.colorScale)
              .clamp(spec.rgbMin, spec.rgbMax)
              .toDouble();
      _values['${spec.keyName}B'] =
          (spec.identityRgb + delta.$3 * spec.colorScale)
              .clamp(spec.rgbMin, spec.rgbMax)
              .toDouble();
    });
    unawaited(_commitWheel(spec));
  }

  void _setMaster(_PrimaryWheelSpec spec, double value) {
    setState(() => _values['${spec.keyName}Master'] = value);
    unawaited(_commitWheel(spec));
  }

  void _resetWheel(_PrimaryWheelSpec spec) {
    setState(() {
      _pucks[spec.keyName] = Offset.zero;
      _values['${spec.keyName}R'] = spec.identityRgb;
      _values['${spec.keyName}G'] = spec.identityRgb;
      _values['${spec.keyName}B'] = spec.identityRgb;
      _values['${spec.keyName}Master'] = spec.identityMaster;
    });
    unawaited(_commitWheel(spec));
  }

  void _resetAll() {
    setState(() {
      for (final spec in _specs) {
        _pucks[spec.keyName] = Offset.zero;
        _values['${spec.keyName}R'] = spec.identityRgb;
        _values['${spec.keyName}G'] = spec.identityRgb;
        _values['${spec.keyName}B'] = spec.identityRgb;
        _values['${spec.keyName}Master'] = spec.identityMaster;
      }
    });
    unawaited(widget.dispatch('color.primaryWheels', 'reset'));
  }

  @override
  Widget build(BuildContext context) => _WheelPanel(
        title: 'Primary Wheels',
        subtitle: 'Lift · Gamma · Gain · Offset',
        supported: widget.supported,
        onResetAll: _resetAll,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = constraints.maxWidth >= 540
                ? (constraints.maxWidth - 30) / 4
                : (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 12,
              children: <Widget>[
                for (final spec in _specs)
                  SizedBox(
                    width: tileWidth,
                    child: _WheelTile(
                      title: spec.title,
                      enabled: widget.supported,
                      puck: _pucks[spec.keyName] ?? Offset.zero,
                      onPuckChanged: (value) => _setPuck(spec, value),
                      onReset: () => _resetWheel(spec),
                      red: _value('${spec.keyName}R'),
                      green: _value('${spec.keyName}G'),
                      blue: _value('${spec.keyName}B'),
                      master: _value('${spec.keyName}Master'),
                      masterIdentity: spec.identityMaster,
                      masterMin: spec.masterMin,
                      masterMax: spec.masterMax,
                      onMasterChanged: (value) => _setMaster(spec, value),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

class ProfessionalLogWheelsControls extends StatefulWidget {
  const ProfessionalLogWheelsControls({
    super.key,
    required this.supported,
    required this.dispatch,
  });

  final bool supported;
  final ColorWheelDispatch dispatch;

  @override
  State<ProfessionalLogWheelsControls> createState() =>
      _ProfessionalLogWheelsControlsState();
}

class _ProfessionalLogWheelsControlsState
    extends State<ProfessionalLogWheelsControls> {
  static const _ranges = <(String, String)>[
    ('shadows', 'Shadows'),
    ('midtones', 'Midtones'),
    ('highlights', 'Highlights'),
    ('global', 'Global'),
  ];

  final _pucks = <String, Offset>{
    for (final range in _ranges) range.$1: Offset.zero,
  };
  final _values = <String, double>{
    for (final range in _ranges) ...<String, double>{
      '${range.$1}.r': 0,
      '${range.$1}.g': 0,
      '${range.$1}.b': 0,
      '${range.$1}.master': 0,
    },
    'shadowPivot': 0.33,
    'highlightPivot': 0.67,
    'transitionWidth': 0.10,
  };

  double _value(String key) => _values[key] ?? 0;

  Future<void> _commitWheel(String range) => widget.dispatch(
        'color.logWheels',
        'setWheel',
        <String, Object?>{
          'range': range,
          'r': _value('$range.r'),
          'g': _value('$range.g'),
          'b': _value('$range.b'),
          'master': _value('$range.master'),
        },
      );

  void _setPuck(String range, Offset puck) {
    final delta = _chromaticDelta(puck);
    setState(() {
      _pucks[range] = puck;
      _values['$range.r'] = (delta.$1 * 1.60).clamp(-2.0, 2.0).toDouble();
      _values['$range.g'] = (delta.$2 * 1.60).clamp(-2.0, 2.0).toDouble();
      _values['$range.b'] = (delta.$3 * 1.60).clamp(-2.0, 2.0).toDouble();
    });
    unawaited(_commitWheel(range));
  }

  void _setMaster(String range, double value) {
    setState(() => _values['$range.master'] = value);
    unawaited(_commitWheel(range));
  }

  void _resetWheel(String range) {
    setState(() {
      _pucks[range] = Offset.zero;
      _values['$range.r'] = 0;
      _values['$range.g'] = 0;
      _values['$range.b'] = 0;
      _values['$range.master'] = 0;
    });
    unawaited(_commitWheel(range));
  }

  void _setRangeParameter(String key, double value) {
    setState(() => _values[key] = value);
    unawaited(widget.dispatch('color.logWheels', key, value));
  }

  void _resetAll() {
    setState(() {
      for (final range in _ranges) {
        _pucks[range.$1] = Offset.zero;
        _values['${range.$1}.r'] = 0;
        _values['${range.$1}.g'] = 0;
        _values['${range.$1}.b'] = 0;
        _values['${range.$1}.master'] = 0;
      }
      _values['shadowPivot'] = 0.33;
      _values['highlightPivot'] = 0.67;
      _values['transitionWidth'] = 0.10;
    });
    unawaited(widget.dispatch('color.logWheels', 'reset'));
  }

  @override
  Widget build(BuildContext context) => _WheelPanel(
        title: 'Log Wheels',
        subtitle: 'Shadows · Midtones · Highlights · Global',
        supported: widget.supported,
        onResetAll: _resetAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = constraints.maxWidth >= 540
                    ? (constraints.maxWidth - 30) / 4
                    : (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 12,
                  children: <Widget>[
                    for (final range in _ranges)
                      SizedBox(
                        width: tileWidth,
                        child: _WheelTile(
                          title: range.$2,
                          enabled: widget.supported,
                          puck: _pucks[range.$1] ?? Offset.zero,
                          onPuckChanged: (value) => _setPuck(range.$1, value),
                          onReset: () => _resetWheel(range.$1),
                          red: _value('${range.$1}.r'),
                          green: _value('${range.$1}.g'),
                          blue: _value('${range.$1}.b'),
                          master: _value('${range.$1}.master'),
                          masterIdentity: 0,
                          masterMin: -2,
                          masterMax: 2,
                          onMasterChanged: (value) =>
                              _setMaster(range.$1, value),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF101216),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth >= 520
                      ? (constraints.maxWidth - 20) / 3
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: <Widget>[
                      SizedBox(
                        width: itemWidth,
                        child: _CompactParameter(
                          label: 'Shadow Pivot',
                          value: _value('shadowPivot'),
                          min: 0.05,
                          max: 0.60,
                          enabled: widget.supported,
                          onChanged: (value) =>
                              _setRangeParameter('shadowPivot', value),
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _CompactParameter(
                          label: 'Highlight Pivot',
                          value: _value('highlightPivot'),
                          min: 0.40,
                          max: 0.95,
                          enabled: widget.supported,
                          onChanged: (value) =>
                              _setRangeParameter('highlightPivot', value),
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _CompactParameter(
                          label: 'Transition',
                          value: _value('transitionWidth'),
                          min: 0.01,
                          max: 0.30,
                          enabled: widget.supported,
                          onChanged: (value) =>
                              _setRangeParameter('transitionWidth', value),
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

class _WheelPanel extends StatelessWidget {
  const _WheelPanel({
    required this.title,
    required this.subtitle,
    required this.supported,
    required this.onResetAll,
    required this.child,
  });

  final String title;
  final String subtitle;
  final bool supported;
  final VoidCallback onResetAll;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF17191E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2D33)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  supported ? Icons.check_circle_outline : Icons.info_outline,
                  size: 16,
                  color: supported ? Colors.white60 : Colors.orangeAccent,
                ),
                const SizedBox(width: 5),
                Tooltip(
                  message: 'Reset all',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: supported ? onResetAll : null,
                    icon: const Icon(Icons.restart_alt, size: 18),
                  ),
                ),
              ],
            ),
            const Divider(height: 14, color: Colors.white10),
            child,
          ],
        ),
      );
}

class _WheelTile extends StatelessWidget {
  const _WheelTile({
    required this.title,
    required this.enabled,
    required this.puck,
    required this.onPuckChanged,
    required this.onReset,
    required this.red,
    required this.green,
    required this.blue,
    required this.master,
    required this.masterIdentity,
    required this.masterMin,
    required this.masterMax,
    required this.onMasterChanged,
  });

  final String title;
  final bool enabled;
  final Offset puck;
  final ValueChanged<Offset> onPuckChanged;
  final VoidCallback onReset;
  final double red;
  final double green;
  final double blue;
  final double master;
  final double masterIdentity;
  final double masterMin;
  final double masterMax;
  final ValueChanged<double> onMasterChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
        decoration: BoxDecoration(
          color: const Color(0xFF111318),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                      letterSpacing: 0.55,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Reset $title',
                  child: InkWell(
                    onTap: enabled ? onReset : null,
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.refresh, size: 14, color: Colors.white54),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            AspectRatio(
              aspectRatio: 1,
              child: _ColorWheelSurface(
                enabled: enabled,
                value: puck,
                onChanged: onPuckChanged,
                onReset: onReset,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _RgbReadout(label: 'R', value: red),
                const SizedBox(width: 3),
                _RgbReadout(label: 'G', value: green),
                const SizedBox(width: 3),
                _RgbReadout(label: 'B', value: blue),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                const Text(
                  'Y',
                  style: TextStyle(fontSize: 10, color: Colors.white54),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                    ),
                    child: Slider(
                      min: masterMin,
                      max: masterMax,
                      value: master.clamp(masterMin, masterMax).toDouble(),
                      onChanged: enabled ? onMasterChanged : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 37,
                  child: Text(
                    _formatValue(master, identity: masterIdentity),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _ColorWheelSurface extends StatelessWidget {
  const _ColorWheelSurface({
    required this.enabled,
    required this.value,
    required this.onChanged,
    required this.onReset,
  });

  final bool enabled;
  final Offset value;
  final ValueChanged<Offset> onChanged;
  final VoidCallback onReset;

  Offset _normalized(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.max(1.0, math.min(size.width, size.height) / 2 - 6).toDouble();
    var delta = local - center;
    if (delta.distance > radius) {
      delta = Offset.fromDirection(delta.direction, radius);
    }
    return Offset(
      (delta.dx / radius).clamp(-1.0, 1.0).toDouble(),
      (delta.dy / radius).clamp(-1.0, 1.0).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled
                ? (details) => onChanged(_normalized(details.localPosition, size))
                : null,
            onPanStart: enabled
                ? (details) => onChanged(_normalized(details.localPosition, size))
                : null,
            onPanUpdate: enabled
                ? (details) => onChanged(_normalized(details.localPosition, size))
                : null,
            onDoubleTap: enabled ? onReset : null,
            child: CustomPaint(
              painter: _ColorWheelPainter(value: value, enabled: enabled),
            ),
          );
        },
      );
}

class _ColorWheelPainter extends CustomPainter {
  const _ColorWheelPainter({required this.value, required this.enabled});

  final Offset value;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.max(1.0, math.min(size.width, size.height) / 2 - 6).toDouble();
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 3 / 2,
          colors: const <Color>[
            Color(0xFFFF4C4C),
            Color(0xFFFFD84C),
            Color(0xFF55E36A),
            Color(0xFF4CE7E7),
            Color(0xFF4C72FF),
            Color(0xFFD84CFF),
            Color(0xFFFF4C4C),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[
            Color(0xFFF1F1F1),
            Color(0xBDE5E5E5),
            Color(0x12FFFFFF),
          ],
          stops: <double>[0, 0.46, 1],
        ).createShader(rect),
    );

    final guide = Paint()
      ..color = Colors.black26
      ..strokeWidth = 0.7;
    canvas.drawLine(
      Offset(center.dx - radius * 0.72, center.dy),
      Offset(center.dx + radius * 0.72, center.dy),
      guide,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.72),
      Offset(center.dx, center.dy + radius * 0.72),
      guide,
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = enabled ? Colors.white24 : Colors.white12,
    );

    final puck = center + Offset(value.dx * radius, value.dy * radius);
    canvas.drawCircle(
      puck,
      7,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(
      puck,
      5.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = enabled ? Colors.white : Colors.white38,
    );
    canvas.drawCircle(
      puck,
      2,
      Paint()..color = enabled ? Colors.black87 : Colors.black38,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.enabled != enabled;
}

class _RgbReadout extends StatelessWidget {
  const _RgbReadout({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF090A0D),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.white10),
          ),
          alignment: Alignment.center,
          child: Text(
            '$label ${value.toStringAsFixed(2)}',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(
              fontSize: 8.5,
              color: Colors.white60,
            ),
          ),
        ),
      );
}

class _CompactParameter extends StatelessWidget {
  const _CompactParameter({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                ),
              ),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(fontSize: 9.5, color: Colors.white54),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              min: min,
              max: max,
              value: value.clamp(min, max).toDouble(),
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      );
}

class _PrimaryWheelSpec {
  const _PrimaryWheelSpec({
    required this.title,
    required this.keyName,
    required this.identityRgb,
    required this.identityMaster,
    required this.masterMin,
    required this.masterMax,
    required this.colorScale,
  });

  final String title;
  final String keyName;
  final double identityRgb;
  final double identityMaster;
  final double masterMin;
  final double masterMax;
  final double colorScale;

  double get rgbMin {
    switch (keyName) {
      case 'gamma':
        return 0.01;
      case 'gain':
        return 0;
      default:
        return -4;
    }
  }

  double get rgbMax {
    switch (keyName) {
      case 'gamma':
        return 10;
      case 'gain':
        return 16;
      default:
        return 4;
    }
  }
}

(double, double, double) _chromaticDelta(Offset puck) {
  final radius = math.min(1.0, math.sqrt(puck.dx * puck.dx + puck.dy * puck.dy)).toDouble();
  if (radius <= 0.000001) return (0, 0, 0);

  var hue = math.atan2(-puck.dy, puck.dx) / (math.pi * 2);
  if (hue < 0) hue += 1;
  final h = hue * 6;
  final sector = h.floor() % 6;
  final fraction = h - h.floor();
  final chroma = radius;
  final x = chroma * (1 - (fraction * 2 - 1).abs());

  double r = 0;
  double g = 0;
  double b = 0;
  switch (sector) {
    case 0:
      r = chroma;
      g = x;
      break;
    case 1:
      r = x;
      g = chroma;
      break;
    case 2:
      g = chroma;
      b = x;
      break;
    case 3:
      g = x;
      b = chroma;
      break;
    case 4:
      r = x;
      b = chroma;
      break;
    case 5:
      r = chroma;
      b = x;
      break;
  }

  final mean = (r + g + b) / 3;
  return (r - mean, g - mean, b - mean);
}

String _formatValue(double value, {required double identity}) {
  final delta = value - identity;
  if (delta.abs() < 0.0005) return value.toStringAsFixed(2);
  return value.toStringAsFixed(2);
}
