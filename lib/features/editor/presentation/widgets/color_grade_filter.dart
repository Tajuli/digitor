import 'dart:math' as math;

import 'package:digitor/features/editor/domain/models/color/color_node_graph.dart';
import 'package:flutter/material.dart';

/// Lightweight real-time preview renderer for the node graph.
///
/// Flutter's stock video widget does not expose the decoded texture for custom
/// per-pixel CPU work. This renderer therefore composes a high quality 4x5
/// colour matrix from wheel/primary controls and a linearized approximation of
/// the selected RGB/Y curves. It is fast enough to update while dragging.
class ColorGradeFilter extends StatelessWidget {
  const ColorGradeFilter({super.key, required this.graph, required this.child});

  final ColorNodeGraph graph;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final matrix = _matrixForGraph(graph);
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(matrix),
      child: child,
    );
  }

  /// Returns the same grade used by the Flutter preview as a normalized
  /// column-major 4x4 matrix for Android Media3 export. The fourth column
  /// carries the RGB bias because video pixels have alpha = 1.
  static List<double> exportMatrix4x4(ColorNodeGraph graph) {
    final m = _matrixForGraph(graph);
    return <double>[
      m[0], m[5], m[10], 0,
      m[1], m[6], m[11], 0,
      m[2], m[7], m[12], 0,
      m[4] / 255.0, m[9] / 255.0, m[14] / 255.0, 1,
    ];
  }

  static List<double> _matrixForGraph(ColorNodeGraph graph) {
    var m = _identity();
    for (final node in graph.nodes) {
      if (!node.supportsProcessing || !node.enabled) continue;
      m = _multiply(_nodeMatrix(node), m);
    }
    return m;
  }

  static List<double> _nodeMatrix(ColorNode node) {
    final g = node.grade;
    final wheels = node.wheels;

    // Primaries / wheels.
    final exposure = math.pow(2.0, g.exposure * 1.6).toDouble();
    final contrast = 1.0 + g.contrast * 1.15;
    final saturation = math.max(0.0, 1.0 + g.saturation * 1.35);
    final colorBoost = math.max(0.0, 1.0 + g.colorBoost * .85);

    // Temperature and tint are represented as opposing channel gains.
    final warm = g.temperature * .24;
    final tint = g.tint * .18;
    var rGain = exposure * (1 + warm + tint * .25);
    var gGain = exposure * (1 - tint);
    var bGain = exposure * (1 - warm + tint * .25);

    // Lift/shadows and gain/highlights. Values are deliberately bounded to
    // prevent a dragged control from instantly clipping the preview.
    final lift = g.shadows * 46.0;
    final gain = 1.0 + g.highlights * .55;
    rGain *= gain;
    gGain *= gain;
    bGain *= gain;

    // Curves: approximate each channel using its end-to-end slope and midpoint
    // bias. This makes every curve channel visibly affect live playback while
    // retaining GPU-backed ColorFiltered performance.
    final curves = node.curves;
    final yCurve = curves.previewEnabled ? _linearize(curves.y) : (1.0, 0.0);
    final rCurve = curves.previewEnabled ? _linearize(curves.r) : (1.0, 0.0);
    final gCurve = curves.previewEnabled ? _linearize(curves.g) : (1.0, 0.0);
    final bCurve = curves.previewEnabled ? _linearize(curves.b) : (1.0, 0.0);
    rGain *= yCurve.$1 * rCurve.$1;
    gGain *= yCurve.$1 * gCurve.$1;
    bGain *= yCurve.$1 * bCurve.$1;
    final rBias = lift + 255 * (yCurve.$2 + rCurve.$2);
    final gBias = lift + 255 * (yCurve.$2 + gCurve.$2);
    final bBias = lift + 255 * (yCurve.$2 + bCurve.$2);

    var base = <double>[
      rGain, 0, 0, 0, rBias,
      0, gGain, 0, 0, gBias,
      0, 0, bGain, 0, bBias,
      0, 0, 0, 1, 0,
    ];

    // Lift/Gamma/Gain/Offset wheels. A 4x5 colour matrix cannot isolate
    // tonal ranges as precisely as a shader, but these weighted channel
    // gains and biases provide responsive, persistent live preview.
    if (wheels.previewEnabled) {
      base = _multiply(_wheelMatrix(wheels), base);
    }

    // Contrast around middle grey.
    final contrastBias = 128.0 * (1.0 - contrast);
    base = _multiply(<double>[
      contrast, 0, 0, 0, contrastBias,
      0, contrast, 0, 0, contrastBias,
      0, 0, contrast, 0, contrastBias,
      0, 0, 0, 1, 0,
    ], base);

    // Standard luminance-preserving saturation matrix.
    const lr = .2126, lg = .7152, lb = .0722;
    final inv = 1 - saturation;
    base = _multiply(<double>[
      inv * lr + saturation, inv * lg, inv * lb, 0, 0,
      inv * lr, inv * lg + saturation, inv * lb, 0, 0,
      inv * lr, inv * lg, inv * lb + saturation, 0, 0,
      0, 0, 0, 1, 0,
    ], base);

    // Color Boost is a gentler vibrance-style saturation pass.
    final boostInv = 1 - colorBoost;
    base = _multiply(<double>[
      boostInv * lr + colorBoost, boostInv * lg, boostInv * lb, 0, 0,
      boostInv * lr, boostInv * lg + colorBoost, boostInv * lb, 0, 0,
      boostInv * lr, boostInv * lg, boostInv * lb + colorBoost, 0, 0,
      0, 0, 0, 1, 0,
    ], base);

    // Hue rotation around the luminance axis. Range -1...1 maps to -180...180 degrees.
    if (g.hue.abs() > .0001) {
      final angle = g.hue * math.pi;
      final c = math.cos(angle);
      final si = math.sin(angle);
      base = _multiply(<double>[
        .213 + c * .787 - si * .213, .715 - c * .715 - si * .715, .072 - c * .072 + si * .928, 0, 0,
        .213 - c * .213 + si * .143, .715 + c * .285 + si * .140, .072 - c * .072 - si * .283, 0, 0,
        .213 - c * .213 - si * .787, .715 - c * .715 + si * .715, .072 + c * .928 + si * .072, 0, 0,
        0, 0, 0, 1, 0,
      ], base);
    }

    // Qualifier preview: when enabled, strengthen the selected hue family and
    // reduce unselected colour energy. It is an intentionally fast preview
    // approximation; export/native renderers can later use the persisted HSL
    // ranges for a true matte.
    final q = node.qualifier;
    if (q.enabled) {
      final hue = q.hueCenter - q.hueCenter.floorToDouble();
      final selected = HSVColor.fromAHSV(1, hue * 360, 1, 1).toColor();
      final sr = selected.red / 255.0;
      final sg = selected.green / 255.0;
      final sb = selected.blue / 255.0;
      final width = q.hueWidth.clamp(.02, 1.0);
      final strength = (1 - width) * .55 + .12;
      final direction = q.inverted ? -1.0 : 1.0;
      base = _multiply(<double>[
        1 + direction * strength * sr, 0, 0, 0, 0,
        0, 1 + direction * strength * sg, 0, 0, 0,
        0, 0, 1 + direction * strength * sb, 0, 0,
        0, 0, 0, 1, 0,
      ], base);
    }

    return base;
  }


  static List<double> _wheelMatrix(ColorWheelSettings wheels) {
    // Stronger Resolve-style primaries. Lift primarily changes the black point,
    // gamma reshapes the middle range, gain controls highlights, and offset
    // moves the whole signal. The matrix path is still real-time and is also
    // shared with export, so preview and rendered output remain consistent.
    final lift = _wheelRgb(wheels.lift, chromaStrength: .34, luminanceStrength: 58);
    final gamma = _wheelRgb(wheels.gamma, chromaStrength: .32, luminanceStrength: .48);
    final gain = _wheelRgb(wheels.gain, chromaStrength: .44, luminanceStrength: .78);
    final offset = _wheelRgb(wheels.offset, chromaStrength: .38, luminanceStrength: 72);

    final gammaLum = gamma.$4;
    final gainLum = gain.$4;
    final rScale = (1 + gamma.$1 + gammaLum + gain.$1 + gainLum).clamp(.03, 4.0).toDouble();
    final gScale = (1 + gamma.$2 + gammaLum + gain.$2 + gainLum).clamp(.03, 4.0).toDouble();
    final bScale = (1 + gamma.$3 + gammaLum + gain.$3 + gainLum).clamp(.03, 4.0).toDouble();

    final rBias = lift.$1 * 255 + lift.$4 + offset.$1 * 255 + offset.$4;
    final gBias = lift.$2 * 255 + lift.$4 + offset.$2 * 255 + offset.$4;
    final bBias = lift.$3 * 255 + lift.$4 + offset.$3 * 255 + offset.$4;

    return <double>[
      rScale, 0, 0, 0, rBias,
      0, gScale, 0, 0, gBias,
      0, 0, bScale, 0, bBias,
      0, 0, 0, 1, 0,
    ];
  }

  static (double, double, double, double) _wheelRgb(
    ColorWheelControl control, {
    required double chromaStrength,
    required double luminanceStrength,
  }) {
    final x = control.chroma.dx.clamp(-1.0, 1.0).toDouble();
    final y = control.chroma.dy.clamp(-1.0, 1.0).toDouble();

    // Horizontal axis runs green/cyan <-> magenta/red. Vertical axis runs
    // yellow/green <-> blue. The conversion is neutral at the centre.
    final red = (x * .86 - y * .28) * chromaStrength;
    final green = (-x * .45 - y * .45) * chromaStrength;
    final blue = (-x * .41 + y * .73) * chromaStrength;
    final luminance = control.luminance.clamp(-1.0, 1.0).toDouble() * luminanceStrength;
    return (red, green, blue, luminance);
  }

  static (double, double) _linearize(List<Offset> points) {
    if (points.length < 2) return (1, 0);
    final sorted = [...points]..sort((a, b) => a.dx.compareTo(b.dx));
    double sample(double x) {
      for (var i = 0; i < sorted.length - 1; i++) {
        final a = sorted[i], b = sorted[i + 1];
        if (x >= a.dx && x <= b.dx) {
          final span = math.max(.0001, b.dx - a.dx);
          final t = (x - a.dx) / span;
          return a.dy + (b.dy - a.dy) * t;
        }
      }
      return x <= sorted.first.dx ? sorted.first.dy : sorted.last.dy;
    }

    final y25 = sample(.25), y75 = sample(.75);
    final slope = ((y75 - y25) / .5).clamp(.05, 3.0).toDouble();
    final midpoint = sample(.5);
    final bias = (midpoint - slope * .5).clamp(-1.0, 1.0).toDouble();
    return (slope, bias);
  }

  static List<double> _identity() => <double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static List<double> _multiply(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var value = col == 4 ? a[row * 5 + 4] : 0.0;
        for (var k = 0; k < 4; k++) {
          value += a[row * 5 + k] * b[k * 5 + col];
        }
        out[row * 5 + col] = value;
      }
    }
    return out;
  }
}
