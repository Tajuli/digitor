# Digitor

Digitor is the **UI/UX application layer** for the Digitor video editor. All editing and media-processing responsibilities belong to [DigitorEngine](https://github.com/Tajuli/DigitorEngine).

This repository was intentionally rebuilt from a clean snapshot. The old application-side media, render, timeline, and export implementations are not part of the new architecture.

## Ownership boundary

### Digitor owns
- Flutter UI and UX
- layout, navigation, gestures, shortcuts and accessibility
- presentation-only state
- displaying engine snapshots, errors and progress
- forwarding user intent to the engine through a thin gateway

### DigitorEngine owns
- media import, probing and decode
- project and timeline domain state
- playback and frame rendering
- transforms, color, effects, compositing and audio processing
- render scheduling and GPU/CPU backend execution
- encoding and export
- cancellation, progress and engine errors

## Non-negotiable rule

No codec, FFmpeg/media backend, timeline calculation, effect implementation, renderer, encoder or exporter may be implemented in this Flutter application. If a feature changes pixels, audio, timing, project state or export output, it belongs in DigitorEngine.

## Current foundation

The Flutter side currently contains only a minimal editor presentation shell and an abstract `EngineGateway`. The gateway is intentionally ABI-agnostic: the concrete native/FFI adapter must bind to verified public DigitorEngine APIs rather than duplicating or inventing engine behavior in Dart.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the integration contract.
