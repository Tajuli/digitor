import 'package:digitor/app/digitor_app.dart';
import 'package:digitor/features/editor/domain/models/media_item.dart';
import 'package:digitor/features/editor/presentation/editor_page.dart';
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
    expect(find.text('Video Preview'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    for (final label in [
      'Trim',
      'Text',
      'Filter',
      'Adjust',
      'Crop',
      'Sticker',
      'Audio',
      'Export',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    expect(find.text('Video 1'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });
}
