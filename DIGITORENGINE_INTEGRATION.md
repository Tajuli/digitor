# DigitorEngine integration

Digitor is being converted into a UI/UX shell around `DigitorEngine`.

## Ownership rule

Flutter/Dart may own presentation state, gestures, menus, dialogs, layout, selection visuals and user-facing progress/status display. It must not implement a second media pipeline.

`DigitorEngine` is the authoritative owner of:

- media open/probe and decode
- timeline transport and timeline processing
- audio/video synchronization
- preview frame selection and rendering
- GPU backend selection and CPU fallback policy
- node graph topology and execution
- color correction, Primary Wheels, Log Wheels, RGB Curves and HSL Qualifier
- LUTs, effects and Power Windows
- production preview resources / Flutter texture presentation
- export rendering, encoding orchestration, progress and cancellation

## App boundary

All editor commands must pass through `DigitorEngineGateway`, which owns one `DigitorEditorWorkspace`.

```text
Flutter UI / UX
      |
      v
DigitorEngineGateway
      |
      v
DigitorEditorWorkspace
      |
      +-- media/decode
      +-- timeline/playback/audio sync
      +-- production GPU preview
      +-- node/color/effects
      +-- export
```

Flutter models may remain temporarily as view models during migration, but they must not be treated as the render/export source of truth.

## Legacy paths to remove during cut-over

The following current app-side paths are transitional and must not remain in the final engine-owned architecture:

- `video_player`-driven decode/playback in `PlaybackController`
- Flutter-side preview color processing in `ColorGradeFilter`
- `digitor/mobile_export` custom export pipeline in `MobileExportService`
- app-side preview proxy/media processing that duplicates engine responsibilities
- app-side timeline/render calculations that determine media output independently of the engine

File picking and save-location UI may remain in Flutter because they are user-interface/platform-document-picker concerns. Once a path/URI is chosen, media ownership transfers immediately to `DigitorEngine`.

## Production preview requirement

The final preview must use the native texture registered by `digitor_engine_ffi` and the production GPU session. The Flutter widget must display the engine texture only; it must not instantiate `VideoPlayerController` for the edited media.

## Export requirement

Export must be started through `DigitorEditorWorkspace.exportMedia` / the production session. Preview and export must bind the same engine node-graph recipe and parameter revisions. Flutter must not generate an independent color matrix or render recipe.

## Platform qualification

Windows, Android, macOS and iOS each require the `digitor_engine_ffi` platform host to register and present the engine's native GPU resource correctly. A missing production host must fail visibly rather than silently falling back to an app-side player/render path.
