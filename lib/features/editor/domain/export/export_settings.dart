import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum ExportFormat { mp4 }

enum ExportVideoCodec { h264, h265 }

enum ExportQuality { best, high, medium, low, least }

enum ExportAudioCodec { aac }

enum ExportDynamicRange { sdr, hdr10, dolbyVisionAuto }

@immutable
class ExportSettings {
  const ExportSettings({
    this.format = ExportFormat.mp4,
    this.videoCodec = ExportVideoCodec.h264,
    required this.resolution,
    required this.frameRate,
    this.quality = ExportQuality.high,
    this.includeAudio = true,
    this.audioCodec = ExportAudioCodec.aac,
    this.audioBitrateKbps = 192,
    this.audioSampleRate = 48000,
    this.dynamicRange = ExportDynamicRange.sdr,
    this.lutPath,
    this.useProxyForPreview = true,
    this.fileName = 'Digitor Export',
    this.outputUri,
    this.outputLabel,
  });

  final ExportFormat format;
  final ExportVideoCodec videoCodec;
  final Size resolution;
  final int frameRate;
  final ExportQuality quality;
  final bool includeAudio;
  final ExportAudioCodec audioCodec;
  final int audioBitrateKbps;
  final int audioSampleRate;
  final ExportDynamicRange dynamicRange;
  final String? lutPath;
  final bool useProxyForPreview;
  final String fileName;
  final String? outputUri;
  final String? outputLabel;

  int get targetVideoBitrateKbps {
    final pixels = resolution.width * resolution.height;
    final fpsFactor = frameRate / 30;
    final base1080p = switch (quality) {
      ExportQuality.best => 18000,
      ExportQuality.high => 12000,
      ExportQuality.medium => 8000,
      ExportQuality.low => 4500,
      ExportQuality.least => 2500,
    };
    final scaled = base1080p * (pixels / (1920 * 1080)) * fpsFactor;
    final codecFactor = videoCodec == ExportVideoCodec.h265 ? .72 : 1.0;
    return (scaled * codecFactor).round().clamp(700, 80000);
  }

  double estimatedSizeMb(Duration duration) {
    if (duration <= Duration.zero) return 0;
    final totalKbps = targetVideoBitrateKbps +
        (includeAudio ? audioBitrateKbps : 0);
    return totalKbps * duration.inMilliseconds / 1000 / 8 / 1024;
  }

  ExportSettings copyWith({
    ExportFormat? format,
    ExportVideoCodec? videoCodec,
    Size? resolution,
    int? frameRate,
    ExportQuality? quality,
    bool? includeAudio,
    ExportAudioCodec? audioCodec,
    int? audioBitrateKbps,
    int? audioSampleRate,
    ExportDynamicRange? dynamicRange,
    String? lutPath,
    bool? useProxyForPreview,
    String? fileName,
    String? outputUri,
    String? outputLabel,
  }) {
    return ExportSettings(
      format: format ?? this.format,
      videoCodec: videoCodec ?? this.videoCodec,
      resolution: resolution ?? this.resolution,
      frameRate: frameRate ?? this.frameRate,
      quality: quality ?? this.quality,
      includeAudio: includeAudio ?? this.includeAudio,
      audioCodec: audioCodec ?? this.audioCodec,
      audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      dynamicRange: dynamicRange ?? this.dynamicRange,
      lutPath: lutPath ?? this.lutPath,
      useProxyForPreview: useProxyForPreview ?? this.useProxyForPreview,
      fileName: fileName ?? this.fileName,
      outputUri: outputUri ?? this.outputUri,
      outputLabel: outputLabel ?? this.outputLabel,
    );
  }
}

extension ExportLabels on ExportSettings {
  String get codecLabel => switch (videoCodec) {
        ExportVideoCodec.h264 => 'H.264',
        ExportVideoCodec.h265 => 'H.265 (HEVC)',
      };

  String get resolutionLabel =>
      '${resolution.width.round()} × ${resolution.height.round()}';
}
