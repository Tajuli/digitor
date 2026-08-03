#pragma once

#include "digitor/native_platform_provider.hpp"

#include <memory>

namespace flutter {
class TextureRegistrar;
}

struct ID3D12Device;
struct IDXGIAdapter4;

namespace digitor::windows_provider {

struct WindowsProviderContext;

[[nodiscard]] NativePlatformProvider make_windows_native_provider(
    std::shared_ptr<WindowsProviderContext> context);

}  // namespace digitor::windows_provider
