import 'package:digitor/features/editor/application/project_controller.dart';
import 'package:digitor/features/editor/application/timeline_controller.dart';
import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:digitor/features/editor/domain/models/timeline_track.dart';
import 'package:digitor/features/editor/domain/models/track_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProjectController project() => ProjectController(
        project: EditorProject(
          duration: Duration.zero,
          tracks: [
            TimelineTrack(id: 'video', name: 'Video 1', type: TrackType.video),
            TimelineTrack(id: 'audio', name: 'Audio 1', type: TrackType.audio),
          ],
        ),
      );

  test('empty project contains an empty video and audio track', () {
    final controller = project();
    expect(controller.tracks, hasLength(2));
    expect(controller.hasClips, isFalse);
    expect(controller.tracks.every((track) => track.clips.isEmpty), isTrue);
  });

  test('linked video audio moves, unlinks, and undoes as one operation', () {
    final controller = project();
    final timeline = TimelineController(projectController: controller);
    timeline.addVideoWithLinkedAudio(trackId: 'video', path: '/video.mp4', duration: const Duration(seconds: 8), hasAudio: true);
    final video = controller.tracks[0].clips.single;
    final audio = controller.tracks[1].clips.single;
    expect(video.linkGroupId, audio.linkGroupId);

    timeline.moveClip(clipId: video.id, fromTrackId: 'video', toTrackId: 'video', start: const Duration(seconds: 2));
    expect(controller.tracks[1].clips.single.start, const Duration(seconds: 2));
    timeline.unlinkClipGroup(video.id);
    expect(controller.tracks.expand((track) => track.clips).every((clip) => clip.linkGroupId == null), isTrue);
    timeline.history.undo();
    expect(controller.tracks[0].clips.single.linkGroupId, isNotNull);
  });
}
