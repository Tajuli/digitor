# Digitor

Digitor is the Flutter UI/UX client for **DigitorEngine**. The app intentionally contains no independent video-processing engine.

## Editor surfaces

The current UI exposes dedicated workspaces for media/import, professional timeline editing, transform/composite, correction, Primary/Log color grading, RGB Curves, HSL Qualifier, scopes, 1D/3D LUTs, masks/windows, blur/sharpen/glow/grain/vignette/motion-blur effects, production nodes, audio, playback/preview quality, performance/runtime, export/delivery, and engine diagnostics.

The known UI catalog is paired with runtime capability discovery. If DigitorEngine reports a capability that the static catalog does not yet recognize, it still appears under **Engine → Runtime-only capabilities** so engine functionality cannot silently disappear from the application surface.

## Engine boundary

`DigitorApp` creates `DigitorFfiEngineGateway`, which is the Flutter-facing adapter over the `digitor_engine_ffi` package. The package owns the native FFI handles, DigitorEngine workspace/session objects, platform production-host registration and native texture presentation. Flutter owns presentation and command marshalling only; media processing remains in DigitorEngine.

The `digitor_engine_ffi` dependency is pinned to an audited DigitorEngine commit in `pubspec.yaml`. On Windows its Dart native-assets hook builds and bundles `digitor_engine.dll` and the required FFmpeg runtime libraries.

DigitorEngine remains responsible for import/probe/decode, timeline, playback, effects/color/nodes, render execution, audio synchronization, preview frames, hardware/runtime policy, and export.

## Windows build

From the repository root in a VS Code PowerShell terminal:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\build_windows.ps1 -Mode release
```

For a debug build use `-Mode debug`. The script enables Windows desktop, creates the Flutter Windows host when missing, resolves packages, provisions the DigitorEngine FFmpeg SDK/runtime, and runs the Flutter build.

See `ARCHITECTURE.md` for the ownership and capability-completeness rules.
