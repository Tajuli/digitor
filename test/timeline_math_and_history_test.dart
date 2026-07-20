import 'package:digitor/features/editor/application/project_controller.dart';
import 'package:digitor/features/editor/application/timeline_controller.dart';
import 'package:digitor/features/editor/application/timeline_math.dart';
import 'package:digitor/features/editor/domain/models/clip_type.dart';
import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:digitor/features/editor/domain/models/timeline_clip.dart';
import 'package:digitor/features/editor/domain/models/timeline_track.dart';
import 'package:digitor/features/editor/domain/models/track_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimelineMath', () {
    test('converts between duration and pixels and clamps positions', () {
      expect(TimelineMath.durationToPixels(const Duration(seconds: 2), 80), 160);
      expect(TimelineMath.pixelsToDuration(160, 80), const Duration(seconds: 2));
      expect(TimelineMath.clampTimelinePosition(const Duration(seconds: 8), const Duration(seconds: 3)), const Duration(seconds: 3));
    });
  });

  test('magnet snapping is pixel based and can be disabled', () {
    final project = _projectWithClips([_clip('anchor', const Duration(seconds: 2))]);
    final controller = TimelineController(projectController: project, pixelsPerSecond: 80);
    expect(controller.snap(const Duration(milliseconds: 2120)), const Duration(seconds: 2));
    controller.setMagnetEnabled(false);
    expect(controller.snap(const Duration(milliseconds: 2120)), const Duration(milliseconds: 2120));
    controller.setMagnetEnabled(true);
    controller.setZoom(160);
    expect(controller.snap(const Duration(milliseconds: 2060)), const Duration(seconds: 2));
    controller.dispose();
    project.dispose();
  });

  test('move undo redo and trim preserve source offset', () {
    final clip = TimelineClip(id: 'clip', type: ClipType.video, start: Duration.zero, duration: const Duration(seconds: 5), sourceDuration: const Duration(seconds: 10));
    final project = ProjectController(project: EditorProject(duration: const Duration(seconds: 10), tracks: [TimelineTrack(id: 'video', name: 'Video', type: TrackType.video, clips: [clip])]));
    final controller = TimelineController(projectController: project);
    controller.moveClip(clipId: 'clip', fromTrackId: 'video', toTrackId: 'video', start: const Duration(seconds: 2));
    expect(project.tracks.single.clips.single.start, const Duration(seconds: 2));
    controller.history.undo();
    expect(project.tracks.single.clips.single.start, Duration.zero);
    controller.history.redo();
    expect(project.tracks.single.clips.single.start, const Duration(seconds: 2));
    controller.trimClip(trackId: 'video', clipId: 'clip', start: const Duration(seconds: 3), end: const Duration(seconds: 6));
    expect(project.tracks.single.clips.single.duration, const Duration(seconds: 3));
    expect(project.tracks.single.clips.single.sourceStart, const Duration(seconds: 1));
    controller.dispose(); project.dispose();
  });

  group('TimelineController splitClip', () {
    test('returns safely when the track or clip is missing', () {
      final project = _projectWithClips([_clip('clip', Duration.zero)]);
      final controller = TimelineController(projectController: project);

      controller.splitClip(
        trackId: 'missing',
        clipId: 'clip',
        position: const Duration(seconds: 2),
      );
      controller.splitClip(
        trackId: 'video',
        clipId: 'missing',
        position: const Duration(seconds: 2),
      );

      expect(project.tracks.single.clips, hasLength(1));
      controller.dispose();
      project.dispose();
    });

    test('respects a locked track', () {
      final project = _projectWithClips([_clip('clip', Duration.zero)], locked: true);
      final controller = TimelineController(projectController: project);

      controller.splitClip(
        trackId: 'video',
        clipId: 'clip',
        position: const Duration(seconds: 2),
      );

      expect(project.tracks.single.clips, hasLength(1));
      controller.dispose();
      project.dispose();
    });

    test('preserves the second clip source start', () {
      final project = _projectWithClips([
        TimelineClip(
          id: 'clip',
          type: ClipType.video,
          start: const Duration(seconds: 1),
          duration: const Duration(seconds: 6),
          sourceStart: const Duration(seconds: 4),
          sourceDuration: const Duration(seconds: 20),
        ),
      ]);
      final controller = TimelineController(projectController: project);

      controller.splitClip(
        trackId: 'video',
        clipId: 'clip',
        position: const Duration(seconds: 3),
      );

      final second = project.tracks.single.clips.singleWhere(
        (clip) => clip.id != 'clip',
      );
      expect(second.sourceStart, const Duration(seconds: 6));
      controller.dispose();
      project.dispose();
    });
  });

  group('TimelineController rippleMove', () {
    test('returns safely when the track is missing', () {
      final project = _projectWithClips([_clip('clip', Duration.zero)]);
      final controller = TimelineController(projectController: project);

      controller.rippleMove(
        trackId: 'missing',
        clipId: 'clip',
        start: const Duration(seconds: 2),
      );

      expect(project.tracks.single.clips.single.start, Duration.zero);
      controller.dispose();
      project.dispose();
    });

    test('respects a locked track', () {
      final project = _projectWithClips([_clip('clip', Duration.zero)], locked: true);
      final controller = TimelineController(projectController: project);

      controller.rippleMove(
        trackId: 'video',
        clipId: 'clip',
        start: const Duration(seconds: 2),
      );

      expect(project.tracks.single.clips.single.start, Duration.zero);
      controller.dispose();
      project.dispose();
    });

    test('moves the clip and shifts only following clips', () {
      final project = _projectWithClips([
        _clip('before', Duration.zero),
        _clip('moved', const Duration(seconds: 2)),
        _clip('following', const Duration(seconds: 5)),
      ]);
      final controller = TimelineController(projectController: project);

      controller.rippleMove(
        trackId: 'video',
        clipId: 'moved',
        start: const Duration(seconds: 3),
      );

      final clips = project.tracks.single.clips;
      expect(clips.singleWhere((clip) => clip.id == 'before').start, Duration.zero);
      expect(
        clips.singleWhere((clip) => clip.id == 'moved').start,
        const Duration(seconds: 3),
      );
      expect(
        clips.singleWhere((clip) => clip.id == 'following').start,
        const Duration(seconds: 6),
      );
      controller.dispose();
      project.dispose();
    });
  });
}

ProjectController _projectWithClips(List<TimelineClip> clips, {bool locked = false}) {
  return ProjectController(
    project: EditorProject(
      duration: const Duration(seconds: 20),
      tracks: [
        TimelineTrack(
          id: 'video',
          name: 'Video',
          type: TrackType.video,
          locked: locked,
          clips: clips,
        ),
      ],
    ),
  );
}

TimelineClip _clip(String id, Duration start) {
  return TimelineClip(
    id: id,
    type: ClipType.video,
    start: start,
    duration: const Duration(seconds: 1),
  );
}
