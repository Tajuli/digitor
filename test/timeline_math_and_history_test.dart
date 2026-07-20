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
}
