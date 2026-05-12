# AI VTuber Agent — Bug Tracker

## ✅ 已修复 (2026-05-10)

### Bug #1: memory_service.dart:86 正则表达式语法错误

**现象**: `error G97324ACF: String starting with " must end with "`
**根因**: Dart raw string `r'...'` 中 `\'` 无法转义单引号 — raw string 中 `'` 直接结束字符串
**修复**: 改用非 raw 双引号字符串 `RegExp("[...]")` 并正确转义反斜杠

### Bug #2: tts_service.dart:12 `_profileDir` 私有访问

**现象**: `error G75B77105: Member not found: '_profileDir'`
**根因**: `StorageService._profileDir` 是 Dart 私有静态成员 (`_` 前缀)，外部类不可访问
**修复**: 在 `StorageService` 添加 `static String get profileDir => _profileDir` 公开 getter

### Bug #3: vision_service.dart:11 `profileDir` 不存在

**现象**: `error G75B77105: Member not found: 'profileDir'`
**根因**: 同 Bug #2，原本 `StorageService.profileDir` 不存在（public getter 缺失）
**修复**: 同上，添加 public getter 后自动修复

### Bug #4: settings_screen.dart:57 `updateBackendUrl` 方法缺失

**现象**: `error GE5CFE876: The method 'updateBackendUrl' isn't defined for the type 'SettingsProvider'`
**根因**: `SettingsProvider` 未定义该方法
**修复**: 在 `SettingsProvider` 添加 `void updateBackendUrl(String url)` 方法

### Bug #5: 窗口四角矩形 + 顶部标题栏

**现象**: `flutter run` 生成的窗口有标准 Windows 标题栏 + 四角矩形
**期望**: 四角圆端 + 无窗口上边框（现代 Flutter app 风格）
**修复**:

- Win32 层: `flutter_window.cpp` 添加 `DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND`
- Flutter 层: `main.dart` 使用 `TitleBarStyle.hidden` + `windowButtonVisibility: false`
- UI 层: `app.dart` 新增 `AppShell` 自定义标题栏（可拖拽 + min/max/close 按钮）

---

## ✅ 已修复 (2026-05-11)

### Bug #6: window_manager 0.5.1 API 变更 — maximizeOrRestore 不存在

**日期**: 2026-05-11

**现象**: 

```
lib/app.dart(113,42): error: 'maximizeOrRestore' isn't defined for 'WindowManager'.
lib/app.dart(83,40): error: 'maximizeOrRestore' isn't defined for 'WindowManager'.
```

**触发条件**: `flutter pub upgrade --major-versions` 将 `window_manager` 从 `^0.3.9` 升级到 `^0.5.1` 后编译失败。

**根因**: window_manager 0.4.0+ 重构了 API，移除了 `maximizeOrRestore()` 方法。替代 API：

- `windowManager.maximize()` — 最大化
- `windowManager.unmaximize()` — 还原

**修复**: `lib/app.dart` 两处调用替换为条件分支：

- 行 83: `() { if (_isMaximized) { unmaximize(); } else { maximize(); } }`
- 行 113: 同上

---

### Bug #7: flutter_window.cpp 类型转换错误 — int → DWM_WINDOW_CORNER_PREFERENCE

**日期**: 2026-05-11

**现象**:

```
error C2440: "初始化": 无法从"int"转换为"DWM_WINDOW_CORNER_PREFERENCE"
```

**根因**: `#define DWMWCP_ROUND 1` 是 `int` 字面量，新版 Windows SDK 要求强类型枚举。

**修复**: `static_cast<DWM_WINDOW_CORNER_PREFERENCE>(DWMWCP_ROUND)`

**受影响文件**: `windows/runner/flutter_window.cpp:42`

---

### Bug #8: InkWell 缺少 Material 祖先 — 标题栏按钮运行时崩溃

**日期**: 2026-05-11

**现象**:

```
No Material widget found.
_InkResponseStateWidget widgets require a Material widget ancestor
  InkWell:file:///D:/AiVtuber_Agent/lib/app.dart:148:14
```

**根因**: `AppShell` 是裸 `Column`，`InkWell` 向上查找 `Material` 祖先失败。

**修复**: `_windowButton()` 中 `InkWell` → `GestureDetector` + `MouseRegion`

**受影响文件**: `lib/app.dart:148`

---

### Bug #9: RenderFlex 溢出 298722 像素 (由 Bug #8 级联触发)

**日期**: 2026-05-11

**现象**:

```
A RenderFlex overflowed by 298722 pixels on the right.
Row:file:///D:/AiVtuber_Agent/lib/app.dart:96:16
```

**根因**: Bug #8 的 Material 错误导致布局引擎计算异常。修复 #8 后自动解决。

**修复**: 无需单独修复。

---

### Bug #10: 窗口四角矩形 + 有边框 — DWM 圆角未生效

**日期**: 2026-05-11

**现象**: 窗口仍显示标准 Windows 边框，四角为矩形。

**根因**: window_manager 0.5.1 的 `TitleBarStyle.hidden` 可能保留了 `WS_CAPTION` / `WS_THICKFRAME` 样式。

**修复**: 在 `flutter_window.cpp` 原生层移除窗口框架样式：

```cpp
LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
style &= ~(WS_CAPTION | WS_THICKFRAME);
SetWindowLongPtr(hwnd, GWL_STYLE, style);
SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
    SWP_NOZORDER | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
```

**受影响文件**: `windows/runner/flutter_window.cpp`

---

## ✅ 已修复 (2026-05-11 第二批次)

### Bug #11: 窗口 overlay 大于窗口 + 四角矩形（Bug #10 修复不完整）

**日期**: 2026-05-11

**现象**: 窗口四角仍为矩形，且存在一个透明的 overlay 层大于实际窗口。

**根因**: 同时移除 `WS_CAPTION | WS_THICKFRAME` 导致 DWM 停止对该窗口进行合成（compositing），圆角和阴影均失效。移除样式后旧的非客户区（标题栏+边框）未回收，形成透明 ghost overlay。

**修复**: 

- **只移除 `WS_CAPTION`**，保留 `WS_THICKFRAME` — DWM 需要 `WS_THICKFRAME` 来识别该窗口需要合成（圆角、阴影）
- 新增 `DwmExtendFrameIntoClientArea(hwnd, &margins)` — 将 DWM 框架延伸至客户区，使圆角与窗口内容无缝融合（消除边框线）

```cpp
// Correct: keep WS_THICKFRAME for DWM compositing
LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
style &= ~WS_CAPTION;  // only remove caption, keep thickframe
SetWindowLongPtr(hwnd, GWL_STYLE, style);

MARGINS margins = {0, 0, 0, 1};
DwmExtendFrameIntoClientArea(hwnd, &margins);

SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
    SWP_NOZORDER | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
```

**受影响文件**: `windows/runner/flutter_window.cpp`

---

### Bug #12: 标题栏文字下方出现丑下划线

**日期**: 2026-05-11

**现象**: 左上角自定义标题栏 "AI VTuber Agent" 文字下方出现下划线。

**根因**: `TextDecoration` 可能从祖先 Widget 继承了下划线样式（`AppShell` 为裸 `Column`，无 `Material` 祖先隔离 style 继承）。

**修复**: 在标题 `Text` 的 `TextStyle` 显式添加 `decoration: TextDecoration.none`。

**受影响文件**: `lib/app.dart`

---

## ⬜ 待修复

D:\AiVtuber_Agent>flutter run -d windows
Launching lib\main.dart on Windows in debug mode...
CMake Warning (dev) at flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/windows/CMakeLists.txt:31 (add_custom_command):
  The following keywords are not supported when using
  add_custom_command(TARGET): DEPENDS.

  Policy CMP0175 is not set: add_custom_command() rejects invalid arguments.
  Run "cmake --help-policy CMP0175" for policy details.  Use the cmake_policy
  command to set the policy and suppress this warning.
This warning is for project developers.  Use -Wno-dev to suppress it.

D:\AiVtuber_Agent\windows\runner\live2d_overlay_window.cpp(267,1): error C2220: 以下警告被视为错误 [D:\AiVtuber_Agent\build\windows\x64\runner\ai_vtuber_agent.vcxproj]
D:\AiVtuber_Agent\windows\runner\live2d_overlay_window.cpp(267,1): warning C4010: 单行注释包含行继续符 [D:\AiVtuber_Agent\build\windows\x64\runner\ai_vtuber_agent.vcxproj]
D:\AiVtuber_Agent\windows\runner\live2d_overlay_window.cpp(268,26): error C2065: “tempPath”: 未声明的标识符 [D:\AiVtuber_Agent\build\windows\x64\runner\ai_vtuber_agent.vcxproj]
D:\AiVtuber_Agent\windows\runner\live2d_overlay_window.cpp(269,46): error C2065: “tempPath”: 未声明的标识符 [D:\AiVtuber_Agent\build\windows\x64\runner\ai_vtuber_agent.vcxproj]
Building Windows application...                                    18.2s
Error: Build process failed.

---

### Bug #B28: desktop_multi_window 子窗口 flutter_inappwebview 插件未注册

**日期**: 2026-05-11 (发现), 2026-05-12 (根治)

**现象**:

```
MissingPluginException(No implementation found for method createInAppWebView
on channel com.pichillilorenzo/flutter_inappwebview_manager)
```

**根因**: desktop_multi_window 创建新 Flutter Engine 时，PlatformView 插件（InAppWebView）不会自动注册。
这是 Flutter 多窗口 + PlatformView 的已知限制。

**修复**: 绕过 Flutter 插件体系，直接在 C++ 层创建 WebView2：

- 使用 Win32 CreateWindowEx + 原生 WebView2 COM API
- 复用 flutter_inappwebview 内的 WebView2 SDK 头文件和静态库
- 无需任何 Flutter 插件注册

---

## ✅ 已修复 (2026-05-12 — CMake 路径修复)

### Bug #B29: CMake WebView2 SDK 路径错误

**日期**: 2026-05-12

**现象**:

```
CMake Warning: WebView2 SDK not found at
  D:/AiVtuber_Agent/windows/build/windows/x64/packages/Microsoft.Web.WebView2/build/native.

windows/runner/live2d_overlay_window.cpp(4,10): error C1083:
  无法打开包括文件: "WebView2.h": No such file or directory
```

**根因**: CMakeLists.txt 中 `CMAKE_SOURCE_DIR` = `D:/AiVtuber_Agent/windows/`，
但实际 build 目录在 `D:/AiVtuber_Agent/build/`。路径 `CMAKE_SOURCE_DIR/build/...` 
解析为 `D:/AiVtuber_Agent/windows/build/...`（不存在）。

**修复**: 路径改为 `${CMAKE_SOURCE_DIR}/../build/windows/x64/packages/...`。
同时添加 fallback 搜索路径到 flutter ephemeral cache。

**受影响文件**: `windows/runner/CMakeLists.txt`

---

## ✅ 已修复 (2026-05-12 — WRL 编译错误)

### Bug #B30: WRL Callback + private WndProc + static OnEnvironmentCreated 编译错误

**日期**: 2026-05-12

**现象**:

```
error C2248: "WndProc": 无法访问 private 成员
error C2039: "Callback": 不是 "Microsoft::WRL" 的成员
error C2597: 对非静态成员"webview_env_"的非法引用
error C2660: CreateCoreWebView2EnvironmentWithOptions 不接受 3 个参数
```

**根因**:

1. `WndProc` 声明在 `private:` 区域 → 匿名 namespace 的 `RegisterOverlayClass` 无法引用
2. `Microsoft::WRL::Callback` 需要 C++ 异常支持，但项目全局 `_HAS_EXCEPTIONS=0`
3. `OnEnvironmentCreated` 声明为 `static` 但访问了非静态成员 `webview_env_`, `hwnd_`
4. WRL `Callback` 找不到导致编译器认为第4参数缺失

**修复**: 

- `WndProc` 移到 `public:` 区域
- `OnEnvironmentCreated` 改为非静态成员函数
- 完全移除 WRL 依赖，用**手写 COM callback 类**替代 `Microsoft::WRL::Callback`
  - `EnvironmentCompletedHandler` — 实现 `ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler`
  - `ControllerCompletedHandler` — 实现 `ICoreWebView2CreateCoreWebView2ControllerCompletedHandler`
  - 手写 `QueryInterface`/`AddRef`/`Release`/`Invoke`
- CMakeLists.txt 移除不再需要的 `/EHsc /U_HAS_EXCEPTIONS` 覆盖

**受影响文件**:

- `windows/runner/live2d_overlay_window.h` — WndProc public, OnEnvironmentCreated non-static
- `windows/runner/live2d_overlay_window.cpp` — 完全重写
- `windows/runner/CMakeLists.txt` — 清理编译标志

---

## ✅ 已修复 (2026-05-12 — 同步 WebView2 初始化 + COM 引用计数)

### Bug #B33: WebView2 异步初始化永不触发 + COM 引用缺失 → 模型不显示 + Close 崩溃

**日期**: 2026-05-12

**现象**: 
1. `C4010: 单行注释包含行继续符` — 注释 `\` 吞掉下行
2. Overlay 透明但模型不显示
3. Close Overlay 卡退

**根因**:
1. 注释行 `// Default: %TEMP%\AiVtuber_Overlay\` 末尾 `\` 是 C/C++ 行继续符
2. `CreateCoreWebView2EnvironmentWithOptions` 是异步的，回调依赖 COM 消息泵。`CreateOverlay()` 不等回调就返回到 Dart，`pending_url_` 设好了但回调永远不触发 → WebView2 从未就绪，URL 从未加载
3. COM 接口指针（`webview_env_`, `webview_controller_`, `webview_`）裸赋值未调 `AddRef()`/`Release()`，销毁时可能 double-free 或 use-after-free

**修复**:
- 注释 `\` → `/`
- `InitWebView()` 改为**同步**：`CreateCoreWebView2EnvironmentWithOptions` 后用 `PeekMessage`/`DispatchMessage` 循环泵消息直到 `webview_ready_ == true`（10s 超时）。确保返回到 Dart 时 WebView2 已完全初始化、URL 已加载
- COM 指针赋值时调 `AddRef()`，`Destroy()` 中调 `Release()`
- 新增 `destroying_` 标志，回调中检查防止销毁期间操作成员
- 移除 `DwmEnableBlurBehindWindow`（可能与 WebView2 透明冲突）

**受影响文件**:
- `windows/runner/live2d_overlay_window.h` — + destroying_
- `windows/runner/live2d_overlay_window.cpp` — 同步 InitWebView + COM ref + destroying_
- `windows/runner/live2d_overlay_bridge.cpp` — PostMessage WM_CLOSE（前次修复）
