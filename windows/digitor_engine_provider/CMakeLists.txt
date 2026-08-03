cmake_minimum_required(VERSION 3.21)

add_library(digitor_windows_native_provider STATIC
  windows_native_provider.cpp
)

target_compile_features(digitor_windows_native_provider PRIVATE cxx_std_20)
target_compile_definitions(digitor_windows_native_provider PRIVATE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
  DIGITOR_WINDOWS_NATIVE_PROVIDER=1
)

target_include_directories(digitor_windows_native_provider PRIVATE
  "${FLUTTER_MANAGED_DIR}/cpp_client_wrapper/include"
  "${DIGITOR_ENGINE_ROOT}/include"
)

target_link_libraries(digitor_windows_native_provider PRIVATE
  flutter
  Digitor::Engine
  d3d12
  dxgi
  mf
  mfplat
  mfuuid
  shlwapi
)

set_target_properties(digitor_windows_native_provider PROPERTIES
  POSITION_INDEPENDENT_CODE ON
)
