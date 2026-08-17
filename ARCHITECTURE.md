# Digitor architecture

## Non-negotiable ownership boundary

Digitor is the Flutter presentation client. DigitorEngine is the editor.

Digitor may own:
- layout, navigation, gestures and visual interaction state
- inspector widgets, panels, menus and dialogs
- presentation-only selection/hover/expanded state
- marshalling user commands to the engine package
- displaying engine snapshots, progress, telemetry, errors and capabilities

DigitorEngine owns:
- project/media state, import/probe/decode and native surfaces
- authoritative multitrack timeline and all edit operations
- playback scheduling, frame selection, sync, preview quality and proxy policy
- correction, grading, LUTs, masks/windows, effects and node execution
- render graph, shaders, backend selection, GPU/CPU execution and caching
- audio processing/synchronization
- preview rendering and native texture frames
- encoding/export, asynchronous jobs, resume/cancel/progress and errors

There must never be a second Dart implementation of media processing, timeline rendering, grading/effects, playback rendering, or export processing.

## Platform UI family contract

Digitor has two product UI families, selected by target platform rather than window width:

- **Android + iOS:** `MobileEditorScreen`. Both platforms share the same CapCut-inspired mobile editor structure, controls and visual hierarchy. Phone/tablet size may change density and available panel height, but it must not switch to the desktop editor.
- **Windows + macOS:** `EditorScreen`. Both desktop platforms share the same workstation layout, inspector, timeline and node/color workspace structure. Window resizing must not switch to the mobile editor.

This keeps interaction design consistent inside each platform family while still allowing responsive sizing within that family.

## Flutter ↔ DigitorEngine boundary

`DigitorFfiEngineGateway` is the application-facing boundary. It adapts UI intents and read-only UI state to the public `digitor_engine_ffi` Flutter package.

The `digitor_engine_ffi` package owns native FFI bindings, engine/workspace/session handles, platform production-host registration, native texture presentation and native-assets packaging. The application must not open `digitor_engine.dll` directly or duplicate C ABI bindings.

The dependency is pinned to an exact audited DigitorEngine commit in `pubspec.yaml` so app and native ABI move together deliberately.

## Capability completeness rule

`engine_feature_catalog.dart` defines dedicated UI for source-backed DigitorEngine features. At startup the gateway also reports runtime capabilities from the active renderer/production host.

Any runtime capability whose `id` is not yet in the known catalog should remain visible under **Engine → Runtime-only capabilities**. This prevents new or less-common engine functionality from becoming invisible in the app while a dedicated control surface is being added.

A runtime capability record uses:

```text
{
  id: string,
  category: string,
  title: string,
  supported: bool,
  metadata: map
}
```

The active DigitorEngine renderer and production host are the source of truth for whether a capability is available on the device/backend.

## Preview/export identity

Preview and export must consume the same authoritative DigitorEngine project/timeline/node/color state. UI widgets do not calculate a second preview or export transform. A platform/GPU failure is surfaced as an error; the app does not silently request a different execution backend for an active job.
