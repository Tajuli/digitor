# Digitor

Digitor is the Flutter editor application for **DigitorEngine**.

## Architecture

- `Digitor` owns UI, interaction and editor state only.
- `DigitorEngine` owns media decode/import, node graph, color processing, effects, GPU rendering, preview/export primitives and backend selection.
- The app depends on the production Flutter package at `DigitorEngine/dart/digitor_engine_ffi`.
- No Media3/FFmpeg/color-matrix/render pipeline is implemented in the app repository.

## Current clean rebuild

This branch replaces the previous application tree with an engine-first editor shell. It already wires:

- DigitorEngine initialization and renderer/device reporting
- production media opening through DigitorEngine
- serial and parallel node creation/deletion
- Correction
- Primary Wheels
- Log Wheels
- RGB Curves
- HSL Qualifier
- LUT
- Effects
- Power Window
- Flutter native texture host capability probing

Production preview/export must remain graph-bound through DigitorEngine; app-side fallback exporters are intentionally not present.

## Build

```bash
flutter pub get
flutter run -d windows
```

Android, iOS and macOS use the same Flutter application and the same `digitor_engine_ffi` package. iOS/macOS builds require Xcode on macOS.
