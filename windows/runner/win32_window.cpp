#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

constexpr int kFlutterWindowDefaultWidth = 1400;
constexpr int kFlutterWindowDefaultHeight = 900;

COLORREF _kBackgroundColor = RGB(18, 18, 18);

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

LRESULT CALLBACK WndProcHelper(HWND hwnd, UINT msg, WPARAM w, LPARAM l,
                               Win32Window* that) {
  return that->MessageHandler(hwnd, msg, w, l);
}

}  // namespace

Win32Window::Win32Window() {}

Win32Window::~Win32Window() { DestroyWindow(hwnd_); }

bool Win32Window::Create(const std::wstring& title, const Point& origin,
                          const Size& size) {
  WNDCLASS window_class = RegisterWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                               static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  hwnd_ = CreateWindow(
      window_class.lpszClassName, title.c_str(),
      WS_OVERLAPPEDWINDOW | WS_VISIBLE,
      static_cast<int>(origin.x * scale_factor),
      static_cast<int>(origin.y * scale_factor),
      static_cast<int>(size.width * scale_factor),
      static_cast<int>(size.height * scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  return hwnd_ != nullptr;
}

WNDCLASS Win32Window::RegisterWindowClass() {
  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kWindowClassName;
  window_class.style = CS_HREDRAW | CS_VREDRAW;
  window_class.cbClsExtra = 0;
  window_class.cbWndExtra = 0;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hIcon = LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
  window_class.hbrBackground = CreateSolidBrush(_kBackgroundColor);
  window_class.lpszMenuName = nullptr;
  window_class.lpfnWndProc = [](HWND hwnd, UINT msg, WPARAM w, LPARAM l) -> LRESULT {
    auto* that = reinterpret_cast<Win32Window*>(
        GetWindowLongPtr(hwnd, GWLP_USERDATA));
    if (!that && msg == WM_CREATE) {
      auto* cs = reinterpret_cast<CREATESTRUCT*>(l);
      that = static_cast<Win32Window*>(cs->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(that));
    }
    if (that) {
      return WndProcHelper(hwnd, msg, w, l, that);
    }
    return DefWindowProc(hwnd, msg, w, l);
  };
  RegisterClass(&window_class);
  return window_class;
}

void Win32Window::Show() { ShowWindow(hwnd_, SW_SHOWNORMAL); }

bool Win32Window::OnCreate() { return true; }

void Win32Window::OnDestroy() { PostQuitMessage(0); }

LRESULT Win32Window::MessageHandler(HWND hwnd, UINT const message,
                                     WPARAM const wparam,
                                     LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      OnDestroy();
      return 0;
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        SetWindowPos(child_content_, nullptr, rect.left, rect.top,
                     rect.right - rect.left, rect.bottom - rect.top,
                     SWP_NOZORDER);
      }
      return 0;
    }
    case WM_CLOSE:
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;
  }
  return DefWindowProc(hwnd_, message, wparam, lparam);
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, hwnd_);
  RECT frame = GetClientArea();
  SetWindowPos(child_content_, nullptr, frame.left, frame.top,
               frame.right - frame.left, frame.bottom - frame.top,
               SWP_NOZORDER);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(hwnd_, &frame);
  return frame;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}
