import 'dart:io';
import 'dart:math' as math;

/// Lightweight cached waveform preview for timeline clips.
///
/// It samples the media bytes once off the widget build path and converts each
/// bucket to a normalized peak. This works for standalone and embedded audio
/// without adding a platform plugin; cached peaks are reused while scrolling.
class AudioWaveformCache {
  AudioWaveformCache._();

  static final Map<String, Future<List<double>>> _cache = {};

  static Future<List<double>> peaksFor(String path, {int samples = 240}) {
    return _cache.putIfAbsent('$path#$samples', () => _read(path, samples));
  }

  static Future<List<double>> _read(String path, int samples) async {
    final file = File(path);
    if (!await file.exists()) return const [];
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return const [];

    final safeSamples = math.max(24, samples);
    final bucket = math.max(1, bytes.length ~/ safeSamples);
    final peaks = <double>[];
    for (var start = 0; start < bytes.length && peaks.length < safeSamples; start += bucket) {
      final end = math.min(bytes.length, start + bucket);
      var sum = 0.0;
      var maxDeviation = 0.0;
      for (var i = start; i < end; i++) {
        final deviation = (bytes[i] - 127.5).abs() / 127.5;
        sum += deviation;
        if (deviation > maxDeviation) maxDeviation = deviation;
      }
      final average = sum / math.max(1, end - start);
      peaks.add((average * .55 + maxDeviation * .45).clamp(.08, 1.0).toDouble());
    }
    return peaks;
  }
}
