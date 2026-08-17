import 'package:digitor/app/digitor_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android and iOS use the shared mobile editor family', () {
    expect(
      editorSurfaceFamilyFor(TargetPlatform.android),
      EditorSurfaceFamily.mobile,
    );
    expect(
      editorSurfaceFamilyFor(TargetPlatform.iOS),
      EditorSurfaceFamily.mobile,
    );
  });

  test('Windows and macOS use the shared desktop editor family', () {
    expect(
      editorSurfaceFamilyFor(TargetPlatform.windows),
      EditorSurfaceFamily.desktop,
    );
    expect(
      editorSurfaceFamilyFor(TargetPlatform.macOS),
      EditorSurfaceFamily.desktop,
    );
  });
}
