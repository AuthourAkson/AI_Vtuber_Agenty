#include "live2d_overlay_window.h"

#include <dwmapi.h>
#include <WebView2.h>
#include <commctrl.h>
#include <string>

#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "comctl32.lib")

// ─── Hand-rolled COM callbacks (no WRL, works with _HAS_EXCEPTIONS=0) ───

class EnvironmentCompletedHandler final
    : public ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler {
 public:
  using Fn = void (Live2DOverlayWindow::*)(HRESULT, ICoreWebView2Environment*);
  EnvironmentCompletedHandler(Live2DOverlayWindow* o, Fn f)
      : owner_(o), fn_(f), ref_(1) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown ||
        riid == __uuidof(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)) {
      *ppv = this; AddRef(); return S_OK;
    }
    *ppv = nullptr; return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&ref_); }
  ULONG STDMETHODCALLTYPE Release() override {
    ULONG c = InterlockedDecrement(&ref_);
    if (c == 0) delete this;
    return c;
  }
  HRESULT STDMETHODCALLTYPE Invoke(HRESULT r, ICoreWebView2Environment* e) override {
    (owner_->*fn_)(r, e);
    return S_OK;
  }
 private:
  Live2DOverlayWindow* owner_;
  Fn fn_;
  ULONG ref_;
};

class ControllerCompletedHandler final
    : public ICoreWebView2CreateCoreWebView2ControllerCompletedHandler {
 public:
  using Fn = void (Live2DOverlayWindow::*)(HRESULT, ICoreWebView2Controller*);
  ControllerCompletedHandler(Live2DOverlayWindow* o, Fn f)
      : owner_(o), fn_(f), ref_(1) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown ||
        riid == __uuidof(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler)) {
      *ppv = this; AddRef(); return S_OK;
    }
    *ppv = nullptr; return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&ref_); }
  ULONG STDMETHODCALLTYPE Release() override {
    ULONG c = InterlockedDecrement(&ref_);
    if (c == 0) delete this;
    return c;
  }
  HRESULT STDMETHODCALLTYPE Invoke(HRESULT r, ICoreWebView2Controller* c) override {
    (owner_->*fn_)(r, c);
    return S_OK;
  }
 private:
  Live2DOverlayWindow* owner_;
  Fn fn_;
  ULONG ref_;
};

// ─── Helpers ───

namespace {

constexpr const wchar_t kOverlayClass[] = L"LIVE2D_OVERLAY_WINDOW";
constexpr int kResizeBorder = 8;
constexpr UINT_PTR kSubclassId = 0x4C324457;  // "L2DW"

// Subclass proc for the WebView2 child window.
// refData = Live2DOverlayWindow* pointer.
LRESULT CALLBACK WebViewChildSubclass(
    HWND hwnd, UINT msg, WPARAM wp, LPARAM lp,
    UINT_PTR id, DWORD_PTR refData) {
  auto* self = reinterpret_cast<Live2DOverlayWindow*>(refData);
  if (!self) return DefSubclassProc(hwnd, msg, wp, lp);

  switch (msg) {
    case WM_NCHITTEST:
      if (self->click_through_) {
        return HTTRANSPARENT;  // Click-through: mouse transparent
      }
      break;

    case WM_KEYDOWN:
      if (wp == VK_F2) {
        self->SetClickThrough(!self->click_through_);
        return 0;
      }
      if (wp == VK_ESCAPE) {
        PostMessage(self->GetHandle(), WM_CLOSE, 0, 0);
        return 0;
      }
      break;

    case WM_LBUTTONDOWN:
      if (!self->click_through_) {
        // Interactive mode: left-click → start window drag
        PostMessage(self->GetHandle(), WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
        return 0;
      }
      break;

    case WM_NCDESTROY:
      RemoveWindowSubclass(hwnd, WebViewChildSubclass, id);
      break;
  }
  return DefSubclassProc(hwnd, msg, wp, lp);
}

void RegisterOverlayClass(HINSTANCE hInst) {
  static bool done = false;
  if (done) return;
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = Live2DOverlayWindow::WndProc;
  wc.hInstance = hInst;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
  wc.lpszClassName = kOverlayClass;
  RegisterClassExW(&wc);
  done = true;
}

int HitTestResize(HWND hwnd, int x, int y) {
  RECT rc; GetClientRect(hwnd, &rc);
  int w = rc.right - rc.left, h = rc.bottom - rc.top;
  bool L = x < kResizeBorder, R = x > w - kResizeBorder;
  bool T = y < kResizeBorder, B = y > h - kResizeBorder;
  if (L&&T) return HTTOPLEFT;   if (R&&T) return HTTOPRIGHT;
  if (L&&B) return HTBOTTOMLEFT; if (R&&B) return HTBOTTOMRIGHT;
  if (L) return HTLEFT;  if (R) return HTRIGHT;
  if (T) return HTTOP;   if (B) return HTBOTTOM;
  return HTCLIENT;
}

}  // namespace

// ─── Construction ───

Live2DOverlayWindow::Live2DOverlayWindow() = default;
Live2DOverlayWindow::~Live2DOverlayWindow() { Destroy(); }

// ─── Window Creation ───

bool Live2DOverlayWindow::Create(const std::wstring& title,
                                  int x, int y, int w, int h) {
  HINSTANCE hInst = GetModuleHandle(nullptr);
  RegisterOverlayClass(hInst);
  width_ = w; height_ = h;

  // WS_EX_NOREDIRECTIONBITMAP: per-pixel alpha via DWM (transparent background)
  // Note: WS_EX_TOPMOST removed — OBS can still capture non-topmost windows
  DWORD exStyle = WS_EX_NOREDIRECTIONBITMAP;
  DWORD style = WS_POPUP | WS_THICKFRAME | WS_SYSMENU;
  RECT wr = {0, 0, w, h};
  AdjustWindowRectEx(&wr, style, FALSE, exStyle);

  hwnd_ = CreateWindowExW(exStyle, kOverlayClass, title.c_str(), style,
      x, y, wr.right - wr.left, wr.bottom - wr.top,
      nullptr, nullptr, hInst, this);
  if (!hwnd_) return false;

  // WS_EX_NOREDIRECTIONBITMAP tells DWM to composite this window with
  // per-pixel alpha. WebView2 renders the transparent content directly.
  Show(true);
  // Default: click-through so the overlay doesn't block mouse interaction.
  // Must be called AFTER Show() for the extended style to take effect.
  SetClickThrough(true);

  // Register global hotkeys so F2/ESC work even when overlay lacks focus
  RegisterHotKey(hwnd_, 1, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, VK_F2);
  RegisterHotKey(hwnd_, 2, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, 'Q');

  return true;
}

void Live2DOverlayWindow::Show(bool visible) {
  if (hwnd_) ShowWindow(hwnd_, visible ? SW_SHOW : SW_HIDE);
}

// ─── Navigation (called after Create; queues until WebView2 ready) ───

void Live2DOverlayWindow::Navigate(const std::wstring& url) {
  if (webview_ready_ && webview_) {
    webview_->Navigate(url.c_str());
  } else {
    pending_url_ = url;
    if (!webview_env_ && !destroying_) InitWebView();
  }
}

// ─── Move / Resize / Topmost ───

void Live2DOverlayWindow::Move(int x, int y) {
  if (hwnd_) SetWindowPos(hwnd_, nullptr, x, y, 0, 0,
      SWP_NOZORDER | SWP_NOSIZE | SWP_NOACTIVATE);
}
void Live2DOverlayWindow::Resize(int w, int h) {
  if (!hwnd_) return;
  width_ = w; height_ = h;
  DWORD ex = GetWindowLong(hwnd_, GWL_EXSTYLE);
  DWORD st = GetWindowLong(hwnd_, GWL_STYLE);
  RECT wr = {0, 0, w, h}; AdjustWindowRectEx(&wr, st, FALSE, ex);
  SetWindowPos(hwnd_, nullptr, 0, 0, wr.right - wr.left, wr.bottom - wr.top,
      SWP_NOZORDER | SWP_NOMOVE | SWP_NOACTIVATE);
  ResizeWebView();
}
void Live2DOverlayWindow::GetSize(int* w, int* h) {
  if (w) *w = width_; if (h) *h = height_;
}
void Live2DOverlayWindow::SetTopMost(bool on) {
  if (hwnd_) SetWindowPos(hwnd_, on ? HWND_TOPMOST : HWND_NOTOPMOST,
      0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
}

void Live2DOverlayWindow::SetClickThrough(bool enable) {
  click_through_ = enable;
  // The subclass proc checks click_through_ on each WM_NCHITTEST
  // and returns HTTRANSPARENT when true. No window style changes needed.
}

void Live2DOverlayWindow::ExecuteScript(const std::wstring& script) {
  if (webview_ && webview_ready_) {
    webview_->ExecuteScript(script.c_str(), nullptr);
  }
}

// ─── Destroy ───

void Live2DOverlayWindow::Destroy() {
  destroying_ = true;

  // Release COM pointers
  if (webview_controller_) { webview_controller_->Release(); webview_controller_ = nullptr; }
  if (webview_)           { webview_->Release();           webview_ = nullptr; }
  if (webview_env_)       { webview_env_->Release();       webview_env_ = nullptr; }
  webview_ready_ = false;

  // Unregister global hotkeys
  if (hwnd_) {
    UnregisterHotKey(hwnd_, 1);
    UnregisterHotKey(hwnd_, 2);
  }

  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

// ─── WebView2 Init (synchronous — pumps messages until ready) ───

void Live2DOverlayWindow::InitWebView() {
  if (!hwnd_ || destroying_) return;

  wchar_t tmp[MAX_PATH];
  GetTempPathW(MAX_PATH, tmp);
  std::wstring dataDir = std::wstring(tmp) + L"AiVtuber_Overlay";
  CreateDirectoryW(dataDir.c_str(), nullptr);

  auto* handler = new EnvironmentCompletedHandler(
      this, &Live2DOverlayWindow::OnEnvironmentCreated);

  HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, dataDir.c_str(), nullptr, handler);
  if (FAILED(hr)) { handler->Release(); return; }

  // Pump messages until WebView2 environment is created (or timeout)
  // This makes WebView2 init synchronous so the model loads before Dart returns
  MSG msg;
  DWORD deadline = GetTickCount() + 10000;  // 10s timeout
  while (!webview_ready_ && GetTickCount() < deadline) {
    while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessage(&msg);
      if (webview_ready_) break;
    }
    if (!webview_ready_) Sleep(5);
  }
}

void Live2DOverlayWindow::OnEnvironmentCreated(
    HRESULT result, ICoreWebView2Environment* env) {
  if (destroying_ || FAILED(result) || !env) return;
  webview_env_ = env;
  env->AddRef();

  auto* handler = new ControllerCompletedHandler(
      this, &Live2DOverlayWindow::OnControllerCreated);
  env->CreateCoreWebView2Controller(hwnd_, handler);
}

void Live2DOverlayWindow::OnControllerCreated(
    HRESULT result, ICoreWebView2Controller* ctrl) {
  if (destroying_ || FAILED(result) || !ctrl) return;
  webview_controller_ = ctrl;
  ctrl->AddRef();
  ctrl->get_CoreWebView2(&webview_);
  if (webview_) webview_->AddRef();

  // Transparent background
  ICoreWebView2Controller2* c2 = nullptr;
  if (SUCCEEDED(ctrl->QueryInterface(IID_PPV_ARGS(&c2))) && c2) {
    COREWEBVIEW2_COLOR tc = {0, 0, 0, 0};
    c2->put_DefaultBackgroundColor(tc);
    c2->Release();
  }

  // Settings
  ICoreWebView2Settings* s = nullptr;
  if (webview_ && SUCCEEDED(webview_->get_Settings(&s)) && s) {
    s->put_IsScriptEnabled(TRUE);
    s->put_AreDefaultScriptDialogsEnabled(FALSE);
    s->put_IsWebMessageEnabled(TRUE);
    s->put_AreDevToolsEnabled(FALSE);
  }

  webview_ready_ = true;
  ResizeWebView();

  // Subclass the WebView2 child window so left-clicks initiate window drag
  HWND child = FindWindowEx(hwnd_, nullptr, nullptr, nullptr);
  if (child) {
    SetWindowSubclass(child, WebViewChildSubclass, kSubclassId,
                      reinterpret_cast<DWORD_PTR>(this));
  }

  if (!pending_url_.empty() && webview_) {
    webview_->Navigate(pending_url_.c_str());
    pending_url_.clear();
  }
}

void Live2DOverlayWindow::ResizeWebView() {
  if (webview_controller_ && hwnd_) {
    RECT rc; GetClientRect(hwnd_, &rc);
    if (rc.right > rc.left && rc.bottom > rc.top)
      webview_controller_->put_Bounds(rc);
  }
}

// ─── Window Procedure ───

LRESULT CALLBACK Live2DOverlayWindow::WndProc(
    HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  Live2DOverlayWindow* self = nullptr;
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCT*>(lp);
    self = static_cast<Live2DOverlayWindow*>(cs->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = hwnd;
    return DefWindowProc(hwnd, msg, wp, lp);
  }
  self = reinterpret_cast<Live2DOverlayWindow*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (self) return self->HandleMessage(msg, wp, lp);
  return DefWindowProc(hwnd, msg, wp, lp);
}

LRESULT Live2DOverlayWindow::HandleMessage(UINT msg, WPARAM wp, LPARAM lp) {
  switch (msg) {
    case WM_DESTROY:
      hwnd_ = nullptr;
      // DON'T PostQuitMessage — overlay shares thread with Flutter app
      return 0;

    case WM_SIZE:
      width_ = LOWORD(lp); height_ = HIWORD(lp);
      ResizeWebView();
      return 0;

    case WM_DPICHANGED: {
      auto* r = reinterpret_cast<RECT*>(lp);
      SetWindowPos(hwnd_, nullptr, r->left, r->top,
          r->right - r->left, r->bottom - r->top,
          SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }

    case WM_NCHITTEST: {
      // Click-through: return HTTRANSPARENT so mouse passes through entire window
      if (click_through_) return HTTRANSPARENT;
      // Only handle resize edges; client area stays HTCLIENT
      POINT pt = {LOWORD(lp), HIWORD(lp)};
      ScreenToClient(hwnd_, &pt);
      return HitTestResize(hwnd_, pt.x, pt.y);
    }

    case WM_LBUTTONDOWN:
      // Initiate window drag via system command.
      // Works even when clicking on WebView2 child window
      // (unlike returning HTCAPTION from WM_NCHITTEST which
      //  fails if the click lands on a child HWND).
      SendMessage(hwnd_, WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
      return 0;

    case WM_HOTKEY:
      if (wp == 1) {
        // Ctrl+Shift+F2: toggle click-through globally
        SetClickThrough(!click_through_);
      } else if (wp == 2) {
        // Ctrl+Shift+Q: close overlay globally
        Destroy();
      }
      return 0;

    case WM_KEYDOWN:
      if (wp == VK_ESCAPE) { Destroy(); return 0; }
      if (wp == VK_F2) { SetClickThrough(!click_through_); return 0; }
      break;

    case WM_CLOSE:
      Destroy();
      return 0;
  }
  return DefWindowProc(hwnd_, msg, wp, lp);
}
