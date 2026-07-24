import 'dart:async';

import 'package:digitor/features/editor/domain/export/export_settings.dart';
import 'package:digitor/features/editor/domain/models/clip_type.dart';
import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:flutter/services.dart';


class MobileExportCapabilities {
  const MobileExportCapabilities({
    required this.h264Encoder,
    required this.hevcEncoder,
    required this.hevc10BitEncoder,
    required this.dolbyVisionEncoder,
    required this.supports4k60,
    required this.displayHdr10,
    required this.displayDolbyVision,
    required this.displayHlg,
    required this.sdkInt,
    required this.manufacturer,
    required this.model,
  });

  final bool h264Encoder;
  final bool hevcEncoder;
  final bool hevc10BitEncoder;
  final bool dolbyVisionEncoder;
  final bool supports4k60;
  final bool displayHdr10;
  final bool displayDolbyVision;
  final bool displayHlg;
  final int sdkInt;
  final String manufacturer;
  final String model;

  bool get canExportHdr10 => hevcEncoder && hevc10BitEncoder;
  bool get canExportDolbyVision => dolbyVisionEncoder;

  factory MobileExportCapabilities.fromMap(Map<String, dynamic> map) {
    return MobileExportCapabilities(
      h264Encoder: map['h264Encoder'] == true,
      hevcEncoder: map['hevcEncoder'] == true,
      hevc10BitEncoder: map['hevc10BitEncoder'] == true,
      dolbyVisionEncoder: map['dolbyVisionEncoder'] == true,
      supports4k60: map['supports4k60'] == true,
      displayHdr10: map['displayHdr10'] == true,
      displayDolbyVision: map['displayDolbyVision'] == true,
      displayHlg: map['displayHlg'] == true,
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      manufacturer: map['manufacturer'] as String? ?? 'Unknown',
      model: map['model'] as String? ?? 'Unknown',
    );
  }
}

class ExportLocation {
  const ExportLocation({required this.uri, required this.label});

  final String uri;
  final String label;
}

class MobileExportProgress {
  const MobileExportProgress({required this.state, required this.percent});

  final String state;
  final int percent;

  bool get isRunning => state == 'running' || state == 'waiting';
}

class MobileExportService {
  static const MethodChannel _channel = MethodChannel('digitor/mobile_export');


  Future<MobileExportCapabilities> capabilities() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getExportCapabilities',
    );
    return MobileExportCapabilities.fromMap(result ?? const <String, dynamic>{});
  }

  Future<ExportLocation?> chooseLocation(String suggestedFileName) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'chooseLocation',
      {'fileName': _safeMp4Name(suggestedFileName)},
    );
    if (result == null) return null;
    final uri = result['uri'] as String?;
    if (uri == null || uri.isEmpty) return null;
    return ExportLocation(
      uri: uri,
      label: (result['label'] as String?) ?? 'Selected location',
    );
  }

  Future<String> export({
    required EditorProject project,
    required ExportSettings settings,
  }) async {
    final visualClips = project.tracks
        .where((track) => !track.hidden)
        .expand((track) => track.clips)
        .where(
          (clip) =>
              clip.visible &&
              (clip.type == ClipType.video || clip.type == ClipType.image) &&
              clip.data['path'] is String,
        )
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (visualClips.isEmpty) {
      throw StateError('The timeline has no exportable video or image clips.');
    }
    if (settings.outputUri == null || settings.outputUri!.isEmpty) {
      throw StateError('Choose an export location first.');
    }

    final result = await _channel.invokeMethod<String>('startExport', {
      'outputUri': settings.outputUri,
      'fileName': _safeMp4Name(settings.fileName),
      'width': settings.resolution.width.round(),
      'height': settings.resolution.height.round(),
      'frameRate': settings.frameRate,
      'videoBitrate': settings.targetVideoBitrateKbps * 1000,
      'videoCodec': settings.videoCodec.name,
      'dynamicRange': settings.dynamicRange.name,
      'lutPath': settings.lutPath,
      'includeAudio': settings.includeAudio,
      'clips': visualClips
          .map(
            (clip) => {
              'path': clip.data['path'] as String,
              'type': clip.type.name,
              'durationMs': clip.duration.inMilliseconds,
              'sourceStartMs': clip.sourceStart.inMilliseconds,
              'sourceEndMs': clip.sourceStart.inMilliseconds + clip.duration.inMilliseconds,
              'removeAudio': !settings.includeAudio || clip.type == ClipType.image || clip.muted,
            },
          )
          .toList(),
    });
    return result ?? settings.outputLabel ?? 'Export complete';
  }

  Future<MobileExportProgress> progress() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getProgress');
    return MobileExportProgress(
      state: (result?['state'] as String?) ?? 'idle',
      percent: (result?['percent'] as int?) ?? 0,
    );
  }

  Future<void> cancel() => _channel.invokeMethod<void>('cancelExport');

  String _safeMp4Name(String value) {
    var name = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'Digitor Export';
    if (!name.toLowerCase().endsWith('.mp4')) name = '$name.mp4';
    return name;
  }
}
