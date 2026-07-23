import 'package:digitor/app/digitor_app.dart';
import 'package:digitor/features/editor/domain/models/media_item.dart';
import 'package:digitor/features/editor/domain/models/editor_project.dart';
import 'package:digitor/features/editor/application/playback_controller.dart';
import 'package:digitor/features/editor/application/project_controller.dart';
import 'package:digitor/features/editor/application/timeline_controller.dart';
import 'package:digitor/features/editor/presentation/editor_page.dart';
import 'package:digitor/features/editor/presentation/timeline/timeline_view.dart';
import 'package:digitor/features/editor/presentation/widgets/video_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders Digitor home actions', (tester) async {
    await tester.pumpWidget(const DigitorApp());

    expect(find.text('DIGITOR'), findsOneWidget);
    expect(find.text('Professional Video & Image Editor'), findsOneWidget);
    expect(find.text('Video Editor'), findsOneWidget);
    expect(find.text('Image Editor'), findsOneWidget);
    expect(find.text('Share Digitor'), findsOneWidget);
    expect(find.byIcon(Icons.video_library_rounded), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
    expect(find.byIcon(Icons.share_rounded), findsOneWidget);
  });

  testWidgets('renders editor foundation for video media', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: EditorPage(
          media: MediaItem(
            id: 'sample-video',
            path: '/tmp/sample-video.mp4',
            isVideo: true,
            duration: Duration.zero,
            createdAt: DateTime(2026),
          ),
        ),
      ),
    );

    expect(find.text('Editor'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    expect(find.text('Add media to start editing'), findsOneWidget);

    for (final label in [
      'Edit',
      'Color',
      'Filter',
      'Effect',
      'Audio',
      'Export',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    expect(find.text('Video 1'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('VideoPreview builds its loading state', (tester) async {
    final playbackController = PlaybackController();
    addTearDown(playbackController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          child: VideoPreview(playbackController: playbackController),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('TimelineView builds with scroll direction notifications', (tester) async {
    final projectController = ProjectController(
      project: EditorProject(
        duration: Duration(seconds: 10),
        tracks: [],
      ),
    );
    final timelineController = TimelineController(
      projectController: projectController,
    );
    final playbackController = PlaybackController();
    addTearDown(projectController.dispose);
    addTearDown(timelineController.dispose);
    addTearDown(playbackController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 300,
          child: TimelineView(
            controller: projectController,
            timelineController: timelineController,
            playbackController: playbackController,
          ),
        ),
      ),
    );

    expect(find.text('100%'), findsOneWidget);
  });
}
