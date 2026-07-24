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

    // Primaries / wheels.
    final exposure = math.pow(2.0, g.exposure * 1.6).toDouble();
    final contrast = 1.0 + g.contrast * 1.15;
    final saturation = math.max(0.0, 1.0 + g.saturation * 1.35);

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
    final yCurve = _linearize(node.curves.y);
    final rCurve = _linearize(node.curves.r);
    final gCurve = _linearize(node.curves.g);
    final bCurve = _linearize(node.curves.b);
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
