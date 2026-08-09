# Digitor

Digitor is the Flutter UI/UX client for **DigitorEngine**. The app intentionally contains no independent video-processing engine.

## Editor surfaces

The current UI exposes dedicated workspaces for media/import, professional timeline editing, transform/composite, correction, Primary/Log color grading, RGB Curves, HSL Qualifier, scopes, 1D/3D LUTs, masks/windows, blur/sharpen/glow/grain/vignette/motion-blur effects, production nodes, audio, playback/preview quality, performance/runtime, export/delivery, and engine diagnostics.

The known UI catalog is paired with runtime capability discovery. If DigitorEngine reports a capability that the static catalog does not yet recognize, it still appears under **Engine → Runtime-only capabilities** so engine functionality cannot silently disappear from the application surface.

## Engine boundary

Flutter sends commands through `MethodChannelEngineGateway` and renders read-only snapshots/progress/events. Native platform hosts must bind those channels to DigitorEngine and register the production native texture presenter.

Channel protocol:

- `digitor.engine/methods.v1`
- `digitor.engine/snapshots.v1`
- `digitor.engine/progress.v1`
- `digitor.engine/events.v1`

DigitorEngine remains responsible for import/probe/decode, timeline, playback, effects/color/nodes, render execution, audio synchronization, preview frames, hardware/runtime policy, and export.

## Native-host status

DigitorEngine v0.0.1 itself documents that the final Windows, Android, macOS and iOS Flutter native host/presenter adapters remain platform-host responsibilities. This repository therefore never fakes a connected engine: until a native host registers the protocol, the editor visibly reports **Host unavailable** while preserving the full UI surface.

See `ARCHITECTURE.md` for the ownership and capability-completeness rules.
