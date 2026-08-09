# Digitor application architecture

## Principle

Digitor is a presentation client of DigitorEngine. There is exactly one source of truth for editing behavior: **DigitorEngine**.

```text
Flutter widgets / UI
        |
Presentation state + user intents
        |
EngineGateway (thin Dart contract)
        |
Native adapter / FFI binding
        |
DigitorEngine
        |
Import -> decode -> timeline -> render -> encode -> export
```

## Boundary rules

1. Widgets never call platform codecs, render APIs, FFmpeg, encoders or decoders directly.
2. Widgets never calculate authoritative timeline/media state. They render snapshots supplied by the engine.
3. `EngineGateway` contains no media algorithms. It translates UI intent to the native binding and native events to presentation DTOs.
4. Native binding code may marshal data and manage handles, but must not reimplement DigitorEngine logic.
5. Preview and export must consume the same authoritative DigitorEngine project/effect state.
6. Platform differences are resolved inside DigitorEngine/native integration, not in feature widgets.

## App-layer directories

```text
lib/
  main.dart
  app/
    digitor_app.dart
  core/
    engine/
      engine_gateway.dart
  features/
    editor/
      presentation/
        editor_screen.dart
```

## Engine integration sequence

The concrete adapter will be added only against verified public DigitorEngine ABI/API surface. Integration work should proceed in this order:

1. engine lifecycle and capability discovery
2. project/session lifecycle
3. import/probe and media-bin snapshots
4. timeline commands and snapshots
5. playback/preview frame surface
6. effects/color/audio commands
7. export request, progress, cancellation and result

Until a step is connected, the Flutter UI should show an unavailable/not-connected presentation state rather than providing a second implementation.

## Dependency rule

A PR that adds media-processing or editing-domain implementation to `digitor` is architecturally invalid. That implementation must be made in `DigitorEngine` and exposed through the engine boundary instead.
