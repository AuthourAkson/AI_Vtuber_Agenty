#include "live2d_overlay_window.h"
#include <memory>
#include <string>
#include <cstring>

// Simple C API bridge for Dart FFI.
// Each overlay is identified by an opaque handle.
// Current limitation: single overlay at a time (can be extended to map of handles).

static std::unique_ptr<Live2DOverlayWindow> g_overlay;
static int g_next_id = 1;
static int g_current_id = 0;

extern "C" {

/// Create a Live2D overlay window.
/// Returns a window ID (>0) on success, 0 on failure.
__declspec(dllexport) int CreateOverlay(
    const wchar_t* url, int x, int y, int width, int height) {
  // Clean up stale overlay from previous async close
  if (g_overlay && !g_overlay->IsValid()) {
    g_overlay.reset();
    g_current_id = 0;
  }

  if (g_overlay) {
    // Already exists; post close to existing window
    if (g_overlay->IsValid()) {
      PostMessage(g_overlay->GetHandle(), WM_CLOSE, 0, 0);
    }
    g_overlay.reset();
    g_current_id = 0;
  }

  auto win = std::make_unique<Live2DOverlayWindow>();
  std::wstring title = L"AI VTuber - Live2D Overlay";

  if (!win->Create(title, x, y, width, height)) {
    return 0;
  }

  int id = g_next_id++;
  g_current_id = id;
  g_overlay = std::move(win);

  // Navigate to URL (will load once WebView2 is ready)
  if (url && wcslen(url) > 0) {
    g_overlay->Navigate(url);
  }

  return id;
}

/// Destroy the overlay window (async — posts WM_CLOSE via message pump).
__declspec(dllexport) void DestroyOverlay(int window_id) {
  if (window_id != g_current_id) return;
  if (g_overlay && g_overlay->IsValid()) {
    // Post WM_CLOSE so close is handled through the message pump.
    // This avoids deadlocking from calling Close() on the FFI thread.
    PostMessage(g_overlay->GetHandle(), WM_CLOSE, 0, 0);
  }
  // Mark as closed immediately; window will self-destruct shortly.
  g_current_id = 0;
}

/// Move the overlay to a new position.
__declspec(dllexport) void MoveOverlay(int window_id, int x, int y) {
  if (window_id != g_current_id || !g_overlay) return;
  g_overlay->Move(x, y);
}

/// Resize the overlay.
__declspec(dllexport) void ResizeOverlay(int window_id, int width, int height) {
  if (window_id != g_current_id || !g_overlay) return;
  g_overlay->Resize(width, height);
}

/// Navigate to a new URL.
__declspec(dllexport) void NavigateOverlay(int window_id, const wchar_t* url) {
  if (window_id != g_current_id || !g_overlay || !url) return;
  g_overlay->Navigate(url);
}

/// Show or hide the overlay.
__declspec(dllexport) void ShowOverlay(int window_id, int visible) {
  if (window_id != g_current_id || !g_overlay) return;
  g_overlay->Show(visible != 0);
}

/// Set always-on-top.
__declspec(dllexport) void SetOverlayTopMost(int window_id, int topmost) {
  if (window_id != g_current_id || !g_overlay) return;
  g_overlay->SetTopMost(topmost != 0);
}

/// Set click-through mode (WS_EX_TRANSPARENT).
/// When enabled, all mouse events pass through to windows behind.
__declspec(dllexport) void SetOverlayClickThrough(int window_id, int enable) {
  if (window_id != g_current_id || !g_overlay) return;
  g_overlay->SetClickThrough(enable != 0);
}

/// Check if overlay is alive.
__declspec(dllexport) int IsOverlayAlive(int window_id) {
  if (window_id != g_current_id || !g_overlay) return 0;
  return g_overlay->IsValid() ? 1 : 0;
}

/// Get overlay size (outputs into int*).
__declspec(dllexport) void GetOverlaySize(int window_id, int* width, int* height) {
  if (window_id != g_current_id || !g_overlay) {
    if (width) *width = 0;
    if (height) *height = 0;
    return;
  }
  g_overlay->GetSize(width, height);
}

/// Get the native window handle.
__declspec(dllexport) void* GetOverlayHwnd(int window_id) {
  if (window_id != g_current_id || !g_overlay) return nullptr;
  return g_overlay->GetHandle();
}

/// Execute JavaScript in the WebView2.
__declspec(dllexport) void OverlayExecuteScript(int window_id, const wchar_t* script) {
  if (window_id != g_current_id || !g_overlay || !script) return;
  g_overlay->ExecuteScript(script);
}

}  // extern "C"
