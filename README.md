# Digitor

Digitor is the Flutter UI/UX client for **DigitorEngine**. The app intentionally contains no independent video-processing engine.

## Editor surfaces

The UI exposes dedicated workspaces for media/import, professional timeline editing, transform/composite, correction, Primary/Log color grading, RGB Curves, HSL Qualifier, scopes, 1D/3D LUTs, masks/windows, blur/sharpen/glow/grain/vignette/motion-blur effects, production nodes, audio, playback/preview quality, performance/runtime, export/delivery, and engine diagnostics.

The known UI catalog is paired with runtime capability discovery. If DigitorEngine reports a capability that the static catalog does not yet recognize, it still appears under **Engine → Runtime-only capabilities** so engine functionality cannot silently disappear from the application surface.

## Engine boundary

`DigitorApp` creates `DigitorFfiEngineGateway`, the Flutter-facing adapter over the official `digitor_engine_ffi` package that lives in the DigitorEngine repository. The package owns native FFI handles, workspace/session objects, platform production-host registration and native texture presentation. Flutter owns presentation, interaction state and command marshalling only; video/audio processing remains in DigitorEngine.

`digitor_engine_ffi` is pinned in `pubspec.yaml` to the audited DigitorEngine commit `e26d1f59ac0630ead1861920e0560d1be25ecee9`, so a future Engine main update cannot silently change an app build. The package native-assets hook builds and bundles the native engine and required runtime dependencies for each supported host.

## Android build (Windows PowerShell)

After cloning/pulling the repository, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\build_android.ps1 -Mode release
```

The script creates/refreshes the Android Flutter host, resolves the pinned DigitorEngine package and builds `build\app\outputs\flutter-apk\app-release.apk`. Use `-Mode debug` for a debug APK.

## Windows build

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\build_windows.ps1 -Mode release
```

The script enables Windows desktop, creates the Flutter Windows host when missing, resolves packages, provisions the DigitorEngine FFmpeg SDK/runtime, and runs the Flutter build. Use `-Mode debug` for a debug build.

## iOS / macOS

Generate Apple platform hosts on macOS first:

```bash
./tool/bootstrap_apple.sh
```

Then use the normal Flutter build commands for iOS or macOS.

## CI

The pull-request workflow regenerates clean Android, Windows, iOS and macOS hosts, runs Flutter analysis, and performs host builds against the pinned DigitorEngine package. See `ARCHITECTURE.md` for ownership and capability-completeness rules.
