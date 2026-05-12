cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  # "live2d_overlay_window.cpp"   # DISABLED: PyQt6 pet mode replaces C++ overlay (2026-05-13)
  # "live2d_overlay_bridge.cpp"   # DISABLED: PyQt6 pet mode replaces C++ overlay (2026-05-13)
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Force UTF-8 source encoding for MSVC (prevents C4819 warnings)
if(MSVC)
  target_compile_options(${BINARY_NAME} PRIVATE "/utf-8")
endif()

# No special compile flags needed for overlay files.
# They use hand-rolled COM callbacks (no WRL dependency).

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")

# WebView2 SDK DISABLED — PyQt6 pet mode replaces C++ overlay (2026-05-13)
# If re-enabling the C++ overlay, uncomment:
#   1. live2d_overlay_window.cpp + live2d_overlay_bridge.cpp in add_executable above
#   2. The WebView2 SDK block below
# set(WEBVIEW2_DIR "${CMAKE_SOURCE_DIR}/../build/windows/x64/packages/Microsoft.Web.WebView2/build/native")
# if(EXISTS "${WEBVIEW2_DIR}")
#   target_include_directories(${BINARY_NAME} PRIVATE "${WEBVIEW2_DIR}/include")
#   target_link_libraries(${BINARY_NAME} PRIVATE "${WEBVIEW2_DIR}/x64/WebView2LoaderStatic.lib")
#   message(STATUS "WebView2 SDK found at: ${WEBVIEW2_DIR}")
# else()
#   set(WEBVIEW2_FALLBACK "${CMAKE_SOURCE_DIR}/flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/build/webview2/native")
#   if(EXISTS "${WEBVIEW2_FALLBACK}")
#     set(WEBVIEW2_DIR "${WEBVIEW2_FALLBACK}")
#     target_include_directories(${BINARY_NAME} PRIVATE "${WEBVIEW2_DIR}/include")
#     target_link_libraries(${BINARY_NAME} PRIVATE "${WEBVIEW2_DIR}/x64/WebView2LoaderStatic.lib")
#   else()
#     message(WARNING "WebView2 SDK not found. Live2D overlay will not compile.")
#   endif()
# endif()

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
