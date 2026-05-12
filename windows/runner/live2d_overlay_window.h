#ifndef RUNNER_LIVE2D_OVERLAY_WINDOW_H_
#define RUNNER_LIVE2D_OVERLAY_WINDOW_H_

#include <windows.h>
#include <string>
#include <functional>

// Forward declare WebView2 interfaces (avoid full header dependency in .h)
struct ICoreWebView2Environment;
struct ICoreWebView2Controller;
struct ICoreWebView2;
struct ICoreWebView2EnvironmentOptions;
struct ICoreWebView2Controller2;  // for put_DefaultBackgroundColor

/// A transparent, always-on-top window that hosts a WebView2 rendering
/// a Live2D model. Designed for VTube Studio-style streaming overlay.
///
/// Features:
/// - Frameless, transparent background (DWM composition)
/// - Always on top (WS_EX_TOPMOST)
/// - Draggable (drag anywhere on the window to move)
/// - Resizable edges (8px border handles)
/// - WebView2 with transparent background (alpha channel)
/// - Click-through option for streaming
///
/// Usage from Dart FFI:
///   CreateOverlay(url, x, y, w, h) → window_id
///   MoveOverlay(window_id, x, y)
///   ResizeOverlay(window_id, w, h)
///   SetOverlayUrl(window_id, url)
///   SetOverlayTopMost(window_id, bool)
///   DestroyOverlay(window_id)
class Live2DOverlayWindow {
 public:
  Live2DOverlayWindow();
  ~Live2DOverlayWindow();

  // Create the window. Returns false on failure.
  bool Create(const std::wstring& title, int x, int y, int width, int height);

  // Navigate to a URL. Call after window is created and WebView is ready.
  void Navigate(const std::wstring& url);

  // Move the window to (x, y).
  void Move(int x, int y);

  // Resize the window.
  void Resize(int width, int height);

  // Show or hide the window.
  void Show(bool visible = true);

  // Close and destroy the window.
  void Destroy();

  // Set always-on-top.
  void SetTopMost(bool topmost);

  // Get the window size.
  void GetSize(int* width, int* height);

  // Check if window is valid.
  bool IsValid() const { return hwnd_ != nullptr; }

  // Get the native window handle (for FFI).
  HWND GetHandle() const { return hwnd_; }

  // Window procedure (public — needed by RegisterClass)
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);

 private:
  // Instance message handler
  LRESULT HandleMessage(UINT msg, WPARAM wp, LPARAM lp);

  // Create the WebView2 environment and controller
  void InitWebView();

  // Resize the WebView to fill the client area
  void ResizeWebView();

  // Callback for WebView2 environment creation (non-static, needs member access)
  void OnEnvironmentCreated(HRESULT result, ICoreWebView2Environment* env);

  // Callback for WebView2 controller creation
  void OnControllerCreated(HRESULT result, ICoreWebView2Controller* controller);

  HWND hwnd_ = nullptr;
  int width_ = 400;
  int height_ = 600;

  // Current URL to navigate to once WebView is ready
  std::wstring pending_url_;

  // WebView2 state
  ICoreWebView2Environment* webview_env_ = nullptr;
  ICoreWebView2Controller* webview_controller_ = nullptr;
  ICoreWebView2* webview_ = nullptr;
  bool webview_ready_ = false;

  // Set to true during Destroy() to prevent callbacks from touching members
  bool destroying_ = false;

  // Dragging state
  bool dragging_ = false;
  POINT drag_start_{};
};

#endif  // RUNNER_LIVE2D_OVERLAY_WINDOW_H_
