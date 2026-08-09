# Digitor architecture

## Non-negotiable ownership boundary

Digitor is the Flutter presentation client. DigitorEngine is the editor.

Digitor may own:
- layout, navigation, gestures and visual interaction state
- inspector widgets, panels, menus and dialogs
- presentation-only selection/hover/expanded state
- marshalling user commands to the native host
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

There must never be a second Dart implementation of media processing, timeline math, grading/effects, playback, or export.

## Flutter ↔ native protocol

`MethodChannelEngineGateway` is the single Dart boundary.

- methods: `digitor.engine/methods.v1`
- snapshots: `digitor.engine/snapshots.v1`
- progress: `digitor.engine/progress.v1`
- events: `digitor.engine/events.v1`

Required method calls:
- `initialize`
- `discoverCapabilities`
- `dispatch` with `{ action, arguments }`
- `dispose`

Platform hosts bind this protocol to the verified DigitorEngine C/C++ APIs and native Flutter texture presenter. The Dart app must show host-unavailable state instead of emulating engine behavior.

## Capability completeness rule

`engine_feature_catalog.dart` defines dedicated UI for source-backed DigitorEngine v0.0.1 features. At startup the native host must also return `discoverCapabilities()`.

Any runtime capability whose `id` is not yet in the known catalog is automatically displayed in **Engine → Runtime-only capabilities**. This prevents new or less-common engine functionality from becoming invisible in the app while a dedicated control surface is being added.

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

The platform host is the source of truth for whether a capability is available on the active device/backend.

## Preview/export identity

Preview and export must consume the same authoritative DigitorEngine project/timeline/node/color state. UI widgets do not calculate a second preview or export transform. A platform/GPU failure is surfaced as an error; the app does not silently request a different execution backend for an active job.
