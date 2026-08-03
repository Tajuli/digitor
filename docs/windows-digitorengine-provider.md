# Windows DigitorEngine provider rollout

This branch introduces the application-owned Windows provider package required by DigitorEngine's strict native-provider release gate.

It is not release-qualified until the Flutter runner binds the real GPU texture registrar and the hardware encoder callbacks. The provider is intentionally fail-closed when those bindings are absent.

Required completion sequence:

1. Include `windows/digitor_engine_provider` from the Windows runner CMake project.
2. Point DigitorEngine's release configure at `windows_native_provider.cpp` and a stable build identity.
3. Pass the runner-owned Flutter texture registrar, D3D12 device and DXGI adapter into `WindowsProviderContext`.
4. Bind Flutter GPU-surface presentation without CPU pixels.
5. Bind Media Foundation/NVENC/QSV hardware encoding without software fallback.
6. Bind Vulkan external-memory/semaphore conversion when Vulkan is selected.
7. Run the Windows native release preset, consumer tests and physical GPU qualification.
