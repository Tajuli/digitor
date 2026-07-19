import 'package:digitor/app/digitor_app.dart';
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
}
