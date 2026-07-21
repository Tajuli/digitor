import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:digitor/features/editor/domain/models/clip_adjustments.dart';
import 'package:digitor/features/editor/domain/models/clip_type.dart';
import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:digitor/features/editor/domain/models/timeline_clip.dart';
import 'package:digitor/features/editor/domain/models/timeline_track.dart';
import 'package:digitor/features/editor/domain/models/track_type.dart';
import 'package:digitor/features/projects/domain/saved_editor_project.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class ProjectStorageService {
  static const _folderName = 'saved_projects';

  Future<Directory> _projectsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/$_folderName');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<List<SavedEditorProject>> loadProjects() async {
    final directory = await _projectsDirectory();
    final projects = <SavedEditorProject>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        projects.add(_savedProjectFromJson(json));
      } catch (_) {
        // Ignore a damaged project file instead of blocking the whole library.
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<SavedEditorProject?> loadProject(String id) async {
    final directory = await _projectsDirectory();
    final file = File('${directory.path}/$id.json');
    if (!await file.exists()) return null;
    try {
      return _savedProjectFromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<SavedEditorProject?> renameProject({
    required String id,
    required String newName,
  }) async {
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) return null;
    final existing = await loadProject(id);
    if (existing == null) return null;
    final directory = await _projectsDirectory();
    final renamed = SavedEditorProject(
      id: existing.id,
      name: trimmedName,
      updatedAt: DateTime.now(),
      thumbnailPath: existing.thumbnailPath,
      project: existing.project,
    );
    final target = File('${directory.path}/$id.json');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(_savedProjectToJson(renamed)));
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    return renamed;
  }

  Future<bool> deleteProject(String id) async {
    final directory = await _projectsDirectory();
    final projectFile = File('${directory.path}/$id.json');
    final thumbnailFile = File('${directory.path}/$id.jpg');
    var deleted = false;
    if (await projectFile.exists()) {
      await projectFile.delete();
      deleted = true;
    }
    if (await thumbnailFile.exists()) {
      await thumbnailFile.delete();
    }
    return deleted;
  }

  Future<SavedEditorProject> saveProject({
    required String id,
    required String name,
    required EditorProject project,
    String? previousThumbnailPath,
  }) async {
    final directory = await _projectsDirectory();
    final thumbnailPath = await _createThumbnail(
      id: id,
      project: project,
      directory: directory,
      fallback: previousThumbnailPath,
    );
    final saved = SavedEditorProject(
      id: id,
      name: name,
      updatedAt: DateTime.now(),
      thumbnailPath: thumbnailPath,
      project: project,
    );
    final target = File('${directory.path}/$id.json');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(_savedProjectToJson(saved)));
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    return saved;
  }

  Future<String?> _createThumbnail({
    required String id,
    required EditorProject project,
    required Directory directory,
    String? fallback,
  }) async {
    final visualClips = project.tracks
        .where((track) => track.type == TrackType.video)
        .expand((track) => track.clips)
        .where((clip) => clip.type != ClipType.audio)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (visualClips.isEmpty) return fallback;
    final clip = visualClips.first;
    final sourcePath = clip.data['path'] as String?;
    if (sourcePath == null || sourcePath.isEmpty || !File(sourcePath).existsSync()) {
      return fallback;
    }
    final targetPath = '${directory.path}/$id.jpg';
    try {
      if (clip.type == ClipType.video) {
        final generated = await VideoThumbnail.thumbnailFile(
          video: sourcePath,
          thumbnailPath: directory.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 480,
          quality: 78,
          timeMs: clip.sourceStart.inMilliseconds,
        );
        if (generated == null) return fallback;
        final generatedFile = File(generated);
        if (generatedFile.path != targetPath) {
          if (await File(targetPath).exists()) await File(targetPath).delete();
          await generatedFile.copy(targetPath);
        }
        return targetPath;
      }
      await File(sourcePath).copy(targetPath);
      return targetPath;
    } catch (_) {
      return fallback;
    }
  }

  Map<String, dynamic> _savedProjectToJson(SavedEditorProject saved) => {
        'id': saved.id,
        'name': saved.name,
        'updatedAt': saved.updatedAt.toIso8601String(),
        'thumbnailPath': saved.thumbnailPath,
        'project': _projectToJson(saved.project),
      };

  SavedEditorProject _savedProjectFromJson(Map<String, dynamic> json) =>
      SavedEditorProject(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled Project',
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        thumbnailPath: json['thumbnailPath'] as String?,
        project: _projectFromJson(json['project'] as Map<String, dynamic>),
      );

  Map<String, dynamic> _projectToJson(EditorProject project) => {
        'durationUs': project.duration.inMicroseconds,
        'fps': project.fps,
        'canvasWidth': project.canvasSize.width,
        'canvasHeight': project.canvasSize.height,
        'background': project.background.value,
        'tracks': project.tracks.map(_trackToJson).toList(),
      };

  EditorProject _projectFromJson(Map<String, dynamic> json) => EditorProject(
        duration: Duration(microseconds: (json['durationUs'] as num?)?.toInt() ?? 0),
        fps: (json['fps'] as num?)?.toInt() ?? 30,
        canvasSize: Size(
          (json['canvasWidth'] as num?)?.toDouble() ?? 1920,
          (json['canvasHeight'] as num?)?.toDouble() ?? 1080,
        ),
        background: Color((json['background'] as num?)?.toInt() ?? Colors.black.value),
        tracks: ((json['tracks'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_trackFromJson)
            .toList(),
      );

  Map<String, dynamic> _trackToJson(TimelineTrack track) => {
        'id': track.id,
        'name': track.name,
        'type': track.type.name,
        'locked': track.locked,
        'hidden': track.hidden,
        'muted': track.muted,
        'clips': track.clips.map(_clipToJson).toList(),
      };

  TimelineTrack _trackFromJson(Map<String, dynamic> json) => TimelineTrack(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Track',
        type: TrackType.values.byName(json['type'] as String? ?? 'video'),
        locked: json['locked'] as bool? ?? false,
        hidden: json['hidden'] as bool? ?? false,
        muted: json['muted'] as bool? ?? false,
        clips: ((json['clips'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_clipFromJson)
            .toList(),
      );

  Map<String, dynamic> _clipToJson(TimelineClip clip) => {
        'id': clip.id,
        'type': clip.type.name,
        'startUs': clip.start.inMicroseconds,
        'durationUs': clip.duration.inMicroseconds,
        'positionX': clip.position.dx,
        'positionY': clip.position.dy,
        'scale': clip.scale,
        'rotation': clip.rotation,
        'opacity': clip.opacity,
        'visible': clip.visible,
        'locked': clip.locked,
        'sourceStartUs': clip.sourceStart.inMicroseconds,
        'sourceDurationUs': clip.sourceDuration?.inMicroseconds,
        'linkGroupId': clip.linkGroupId,
        'sourceMediaGroupId': clip.sourceMediaGroupId,
        'isEmbeddedAudio': clip.isEmbeddedAudio,
        'colorGroupId': clip.colorGroupId,
        'filter': clip.filter.name,
        'effect': clip.effect.name,
        'volume': clip.volume,
        'muted': clip.muted,
        'adjustments': {
          'exposure': clip.colorAdjustments.exposure,
          'contrast': clip.colorAdjustments.contrast,
          'saturation': clip.colorAdjustments.saturation,
          'temperature': clip.colorAdjustments.temperature,
          'tint': clip.colorAdjustments.tint,
          'highlights': clip.colorAdjustments.highlights,
          'shadows': clip.colorAdjustments.shadows,
        },
        'data': clip.data,
      };

  TimelineClip _clipFromJson(Map<String, dynamic> json) {
    final adjustments = (json['adjustments'] as Map<String, dynamic>?) ?? const {};
    return TimelineClip(
      id: json['id'] as String,
      type: ClipType.values.byName(json['type'] as String),
      start: Duration(microseconds: (json['startUs'] as num?)?.toInt() ?? 0),
      duration: Duration(microseconds: (json['durationUs'] as num?)?.toInt() ?? 0),
      position: Offset(
        (json['positionX'] as num?)?.toDouble() ?? 0,
        (json['positionY'] as num?)?.toDouble() ?? 0,
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 1,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
      visible: json['visible'] as bool? ?? true,
      locked: json['locked'] as bool? ?? false,
      sourceStart: Duration(microseconds: (json['sourceStartUs'] as num?)?.toInt() ?? 0),
      sourceDuration: json['sourceDurationUs'] == null
          ? null
          : Duration(microseconds: (json['sourceDurationUs'] as num).toInt()),
      linkGroupId: json['linkGroupId'] as String?,
      sourceMediaGroupId: json['sourceMediaGroupId'] as String?,
      isEmbeddedAudio: json['isEmbeddedAudio'] as bool? ?? false,
      colorGroupId: json['colorGroupId'] as String?,
      colorAdjustments: ClipColorAdjustments(
        exposure: (adjustments['exposure'] as num?)?.toDouble() ?? 0,
        contrast: (adjustments['contrast'] as num?)?.toDouble() ?? 0,
        saturation: (adjustments['saturation'] as num?)?.toDouble() ?? 0,
        temperature: (adjustments['temperature'] as num?)?.toDouble() ?? 0,
        tint: (adjustments['tint'] as num?)?.toDouble() ?? 0,
        highlights: (adjustments['highlights'] as num?)?.toDouble() ?? 0,
        shadows: (adjustments['shadows'] as num?)?.toDouble() ?? 0,
      ),
      filter: ClipFilterType.values.byName(json['filter'] as String? ?? 'none'),
      effect: ClipEffectType.values.byName(json['effect'] as String? ?? 'none'),
      volume: (json['volume'] as num?)?.toDouble() ?? 1,
      muted: json['muted'] as bool? ?? false,
      data: Map<String, dynamic>.from((json['data'] as Map?) ?? const {}),
    );
  }
}
