# DigitorEngine Windows native provider

This package is the Windows application-owned side of the DigitorEngine production provider contract.

The Flutter runner must supply one shared provider context containing:

- the live `flutter::TextureRegistrar`;
- the renderer-owned `ID3D12Device`;
- the matching `IDXGIAdapter4` and stable adapter identity;
- successful `MFStartup` state.

The final runner binding must use the same device/adapter for timeline rendering, Flutter GPU-surface presentation and hardware encoding. It must not create a second GPU device, map frames to CPU memory or retry through a software encoder.

Before marking the Windows provider production-qualified, wire:

1. `FlutterNativeTextureRegistrar::register_or_present` to a real Flutter `GpuSurfaceTexture` registration/presentation path.
2. `WindowsHardwareEncoderHost` to a hardware Media Foundation, NVENC or QSV session that accepts the adapter-owned resource.
3. Vulkan/DXGI external-memory and external-semaphore conversion when Vulkan is selected.
4. Device-loss, cancellation, atomic finalize and zero-readback telemetry.
5. Real Windows hardware tests and output decode-and-compare evidence.

The current source establishes repository ownership, Windows SDK dependencies, shared-device identity and fail-closed assembly. It intentionally does not report release readiness until the runner callbacks above are bound and physical qualification passes.
