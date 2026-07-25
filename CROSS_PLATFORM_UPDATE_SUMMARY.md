# Cross-platform update summary

Target platforms: Android, iOS, Windows and macOS.

## Included

- Kept `image_picker` for Android/iOS gallery photo and video selection.
- Kept `file_picker` for Windows/macOS media and audio selection.
- Kept the existing in-app color tools and editor UI unchanged.
- Kept `video_player` for Android/iOS/macOS and `video_player_win` for Windows.
- Added `just_audio_windows`, which is required for `just_audio` method-channel
  registration on Windows.
- Prevented repeated audio initialisation failures from flooding the event loop
  and made asynchronous playback failures handled rather than unhandled.
- Preserved iOS Photos, Camera and Microphone usage descriptions.
- Preserved macOS user-selected file read/write sandbox entitlements.

## Required after extraction

Native plugin registration is generated locally. Run:

```bash
flutter clean
flutter pub get
```

Then fully stop the old app process and rebuild; do not rely on hot restart after
adding a native plugin.

## Builds

```bash
flutter build apk --release
flutter build appbundle --release
flutter build windows --release
```

Run these on macOS with Xcode:

```bash
flutter build ios --release --no-codesign
flutter build macos --release
```

## Export limitation inherited from the source project

The source project's production export method channel is implemented natively
for Android. Import, preview, timeline editing, pickers and audio/video playback
are prepared for the four targets, but feature-identical final video export on
iOS, Windows and macOS requires native encoder implementations for those
platforms or a shared cross-platform media engine. This update does not claim
that unimplemented native encoder code exists.
