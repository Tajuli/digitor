# DigitorEngine integration audit

Audited engine commit: `4db9bed7f14e146bf124f78c8c3971b1620a1b1e`

## Result

Digitor is intentionally a Flutter presentation client. DigitorEngine remains the authoritative editor/runtime.

The current Digitor dependency is pinned to the audited DigitorEngine commit through the `digitor_engine_ffi` package. The app does not vendor or duplicate DigitorEngine native rendering code.

## Verified ownership

### Digitor (UI/UX only)

- Flutter layout, navigation, panels, dialogs, gestures and visual interaction state.
- File/save pickers and presentation of engine errors, progress, telemetry and capabilities.
- Conversion of user interactions into typed DigitorEngine commands/parameters.
- Rendering the Flutter texture id produced by DigitorEngine.

### DigitorEngine (authoritative implementation)

- Engine lifecycle and backend selection.
- Media open/probe/decode and production-session ownership.
- GPU/CPU renderer, render graph, shaders and frame processing.
- Node graph and node operations.
- Correction, Primary Wheels, Log Wheels, RGB Curves, HSL Qualifier, LUTs, effects and power windows.
- Timeline/playback and audio synchronization/controls.
- Native Flutter texture presentation.
- Production export and export progress/cancel contract.

## Source audit findings

1. `digitor_engine_ffi` exports a high-level editor API including `DigitorEditorWorkspace` and `DigitorEditorController`. Native handles remain inside the Engine package.
2. `DigitorEditorWorkspace` explicitly owns renderer, node graph, production media/session, Flutter platform host, timeline and export state.
3. Preview and export bind to the same Engine-owned node graph revisions/recipe identity; Digitor must not implement a second processing path.
4. The Engine's own release audit states portable CI does not prove physical GPU execution, native texture registration, zero-copy interop or hardware encoding. Those remain real-device qualification items.
5. Historical implementation truth tables distinguish source implementation from hardware qualification. App UI must therefore report runtime capability rather than assume every GPU path is available on every machine.

## Integration rule

`lib/core/engine/ffi_engine_gateway.dart` is an adapter, not an editor implementation. It may keep presentation/input values needed to build typed Engine parameter objects, but it must never decode frames, transform pixels, execute effects, schedule rendering, encode media or silently implement fallback behavior.

The app dependency must remain pinned to an audited DigitorEngine commit. Updating the Engine requires an explicit dependency update followed by Windows build/runtime qualification.

## Windows qualification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\verify_engine_boundary.ps1
powershell -ExecutionPolicy Bypass -File .\tool\build_windows.ps1 -Mode release
```

Then launch the Release executable and validate on real hardware:

- Engine initializes and reports the expected GPU backend/device.
- Import creates a production session.
- Preview uses the Engine-provided Flutter texture.
- Node/color/effect changes alter Engine graph/parameter revisions.
- Playback/seek work without a Dart-side renderer.
- Export completes through DigitorEngine and matches the active Engine recipe.
- GPU/texture/zero-copy claims are made only when runtime capability reports support.
