# Digitor GPU-First Rendering Audit

## Policy

Digitor must prefer verified hardware/GPU execution and must never report a GPU-capable path while silently executing a CPU/software fallback.

A backend may fall back to CPU only when that fallback is explicit, user-visible, and intentionally enabled by product policy. The current mobile export path is fail-closed: export stops when a verified hardware encoder is unavailable or fails.

## Findings

### Android export — fixed in this branch

- The Media3 encoder factory used `setEnableFallback(true)`. This allowed a requested encoder configuration to silently fall back.
- Capability discovery counted every encoder returned by `MediaCodecList`, including software codecs. This could report H.264/HEVC support even when only a software encoder was available.
- Export did not preflight the requested codec against a verified hardware encoder.

### Android preview

- Flutter `ColorFiltered` is composited by Flutter's rendering pipeline and does not perform a Dart per-pixel CPU loop.
- The current color pipeline is still a matrix approximation, not the final DigitorEngine shader graph. It should not be described as a full native shader implementation.

### iOS, macOS, and Windows

- No native Digitor GPU export backend is wired into this repository for these platforms.
- These platforms must not display a verified GPU-export claim until DigitorEngine is integrated and runtime backend telemetry is available.
- The intended production order remains:
  - Windows: Vulkan -> Direct3D 12 -> explicit CPU fallback only
  - Android: Vulkan/OpenGL ES processing plus hardware MediaCodec encode; no silent software encode
  - Apple: Metal -> explicit CPU fallback only

## Changes in this branch

- Android capability reporting now includes hardware encoders only.
- Android 10+ uses `isHardwareAccelerated` and rejects `isSoftwareOnly` codecs.
- Older Android versions use a conservative codec-name filter to reject common Google/Android/software codecs.
- Export preflights the requested H.264 or HEVC hardware encoder.
- Media3 encoder fallback is disabled.
- Hardware encoder failure returns a clear error instead of silently switching to software.
- Flutter export service validates hardware-only capability before starting export.
- Capability telemetry exposes `hardwareOnly` and hardware encoder names for diagnostics.

## Remaining work before cross-platform GPU-first can be called complete

1. Integrate DigitorEngine through FFI on Windows, Android, macOS, and iOS.
2. Use one render graph and shader implementation for preview and export.
3. Return runtime telemetry from the active backend: selected API, physical adapter/device, encode backend, and whether CPU fallback is active.
4. Add platform integration tests that fail when a GPU label is shown without verified GPU execution.
5. Add pixel-equivalence tests for preview versus export.

Until those items are implemented, the accurate status is: Android hardware-only export enforcement is implemented; full cross-platform native GPU rendering is not yet implemented in this Flutter repository.
