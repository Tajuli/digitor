# Digitor cross-platform readiness

This project is prepared to compile from one Flutter codebase for:

- Android
- iOS
- Windows
- macOS

## Changes included

- Desktop media import uses `file_picker`.
- Android/iOS media import continues to use the native photo library through
  `image_picker`.
- Windows playback is registered through `video_player_win` while Android,
  iOS and macOS continue to use the official `video_player` API.
- Mobile-only thumbnail extraction no longer prevents Windows/macOS imports.
- Preview proxy compression falls back to the original file on Windows and is
  enabled only where the current compression plugin has a native backend.
- iOS photo-library, camera and microphone usage descriptions are included.
- macOS sandbox access allows the user to open and save selected files.

## Build commands

```bash
flutter pub get
flutter build apk --release
flutter build appbundle --release
flutter build windows --release
flutter build macos --release
flutter build ios --release --no-codesign
```

The macOS and iOS commands must run on macOS with Xcode installed. A signed iOS
archive additionally needs an Apple Developer team, bundle identifier and
signing certificates/profiles.

## Current feature boundary

The existing native export engine is implemented through the
`digitor/mobile_export` method channel and is currently Android-specific.
Import, project editing and preview are made cross-platform by this update, but
production video export on iOS, Windows and macOS still needs a native encoder
implementation (or a shared cross-platform FFmpeg/media engine). The app should
not be described as feature-identical on all four platforms until that export
backend is added and tested on real devices.

## Recommended validation

1. Run `flutter analyze`.
2. Test H.264/AAC MP4 import on each platform.
3. Test file access after restarting the macOS app.
4. Test iPhone import through Photos and Files.
5. Add and test platform export implementations before store release.
