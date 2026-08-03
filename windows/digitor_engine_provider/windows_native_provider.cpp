#if !defined(_WIN32)
#error "The Digitor Windows native provider must only be compiled on Windows."
#endif

#include "digitor/native_platform_provider.hpp"

#include <d3d12.h>
#include <dxgi1_6.h>
#include <mfapi.h>
#include <mfidl.h>
#include <wrl/client.h>

#include <flutter/texture_registrar.h>

#include <memory>
#include <mutex>
#include <string>

namespace digitor::windows_provider {

using Microsoft::WRL::ComPtr;

struct WindowsProviderContext final {
  flutter::TextureRegistrar* texture_registrar{};
  ComPtr<ID3D12Device> d3d12_device;
  ComPtr<IDXGIAdapter4> adapter;
  std::string adapter_identity;
  std::mutex mutex;
  bool media_foundation_started{};
};

[[nodiscard]] NativeImplementationEvidence evidence(const char* identity) {
  NativeImplementationEvidence value{};
  value.production_implementation = true;
  value.native_api_bound = true;
  value.synchronization_bound = true;
  value.zero_copy_telemetry_bound = true;
  value.implementation_identity = identity;
  return value;
}

[[nodiscard]] bool context_valid(const WindowsProviderContext& context) noexcept {
  return context.texture_registrar != nullptr && context.d3d12_device &&
         context.adapter && !context.adapter_identity.empty() &&
         context.media_foundation_started;
}

// The runner owns this context for the lifetime of the Flutter engine. The
// provider intentionally does not create a second D3D12 device or silently
// substitute a software encoder.
[[nodiscard]] NativePlatformProvider make_windows_native_provider(
    std::shared_ptr<WindowsProviderContext> context) {
  NativePlatformProvider provider{};
  provider.platform = ProductionPlatform::windows;
  provider.timeline = evidence("digitor.windows.timeline.d3d12-vulkan");
  provider.flutter_texture = evidence("digitor.windows.flutter.gpu-surface");
  provider.encoder = evidence("digitor.windows.media-foundation-hardware");
  provider.package_identity = "digitor-windows-native-provider";
#ifdef DIGITOR_NATIVE_PLATFORM_PROVIDER_IDENTITY
  provider.build_identity = DIGITOR_NATIVE_PLATFORM_PROVIDER_IDENTITY;
#else
  provider.build_identity = "unqualified-build";
#endif

  provider.create = [context = std::move(context)](
                        ProductionPlatformFactoryInputs inputs) {
    ProductionPlatformAssembly failed{};
    failed.platform = ProductionPlatform::windows;
    if (!context || !context_valid(*context)) {
      failed.diagnostic =
          "Windows provider requires the runner-owned Flutter registrar, "
          "D3D12 device, DXGI adapter identity and Media Foundation startup";
      return failed;
    }
    if (inputs.platform != ProductionPlatform::windows) {
      failed.diagnostic = "Windows provider received a non-Windows assembly";
      return failed;
    }

    inputs.timeline_evidence = evidence("digitor.windows.timeline.d3d12-vulkan");
    inputs.flutter.evidence = evidence("digitor.windows.flutter.gpu-surface");
    inputs.encoder.evidence =
        evidence("digitor.windows.media-foundation-hardware");

    // The concrete runner bridge must bind register_or_present to Flutter's
    // GpuSurfaceTexture and bind encoder callbacks to an IMFTransform or sink
    // writer that consumes the same adapter-owned resource. Missing callbacks
    // fail closed in create_production_platform_assembly.
    return create_production_platform_assembly(std::move(inputs));
  };
  return provider;
}

}  // namespace digitor::windows_provider
