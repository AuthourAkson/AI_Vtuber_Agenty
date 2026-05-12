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

Launching lib\main.dart on Windows in debug mode...
CMake Warning (dev) at flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/windows/CMakeLists.txt:31 (add_custom_command):
  The following keywords are not supported when using
  add_custom_command(TARGET): DEPENDS.

  Policy CMP0175 is not set: add_custom_command() rejects invalid arguments.
  Run "cmake --help-policy CMP0175" for policy details.  Use the cmake_policy
  command to set the policy and suppress this warning.
This warning is for project developers.  Use -Wno-dev to suppress it.

lib/main.dart(15,10): error G5FE39F1E: Type 'AppExitResponse' not found. [D:\AiVtuber_Agent\build\windows\x64\flutter\flutter_assemble.vcxproj]
lib/main.dart(17,12): error G4127D1E8: The getter 'AppExitResponse' isn't defined for the type '_AppExitObserver'. [D:\AiVtuber_Agent\build\windows\x64\flutter\flutter_assemble.vcxproj]
D:\Microsoft Visual Studio\2022\BuildTools\MSBuild\Microsoft\VC\v170\Microsoft.CppCommon.targets(254,5): error MSB8066: “D:\AiVtuber_Agent\build\windows\x64\CMakeFiles\c34551fe35923833d11a024e38cb5a47\flutter_windows.dll.rule;D:\AiVtuber_Agent\build\windows\x64\CMakeFiles\d93f91fab4440261b871f34779069aea\flutter_assemble.rule”的自定义生成已退出，代码为 1。 [D:\AiVtuber_Agent\build\windows\x64\flutter\flutter_assemble.vcxproj]
Building Windows application...                                    16.5s
Error: Build process failed.

D:\AiVtuber_Agent>

---

## ✅ 已修复 (2026-05-13)

### Bug #30: WebView2.h not found — C++ overlay compilation blocks build

**日期**: 2026-05-13

**现象**:

```
windows/runner/live2d_overlay_window.cpp(4,10): error C1083:
  无法打开包括文件: "WebView2.h": No such file or directory
CMake Warning: WebView2 SDK not found. Live2D overlay will not compile.
```

**根因**: `live2d_overlay_window.cpp` 和 `live2d_overlay_bridge.cpp` 仍在 CMakeLists.txt 中编译，
但 WebView2 SDK 未安装在预期路径。项目已决定使用 PyQt6 子进程方案替代 C++ overlay（详见 `project.md` 2026-05-13 变更汇总）。

**修复**: `windows/runner/CMakeLists.txt`

1. 注释 `add_executable` 中的 `live2d_overlay_window.cpp` 和 `live2d_overlay_bridge.cpp`
2. 注释整个 WebView2 SDK 查找/链接块
3. 保留注释中的恢复说明（如需重新启用 C++ overlay）

---

### 

---

## ✅ 已修复 (2026-05-13 下午)

### Bug #31: didRequestAppExit 返回类型不匹配

**日期**: 2026-05-13

**现象 (第一次)**:
```
error: The return type 'Future<bool>' does not match 'Future<AppExitResponse>'
```

**现象 (第二次，改为 AppExitResponse 后)**:
```
error: Type 'AppExitResponse' not found.
error: The getter 'AppExitResponse' isn't defined.
```

**根因**: Flutter SDK 的 `WidgetsBindingObserver.didRequestAppExit()` 方法签名在部分中间版本中
返回 `Future<AppExitResponse>`，但 `AppExitResponse` 枚举在某些 Flutter 引擎缓存版本中未正确导出。

**修复**: `lib/main.dart`
- 放弃使用 `WidgetsBindingObserver` / `didRequestAppExit()`
- 改用 `dart:io` 的 `ProcessSignal.sigterm.watch()` 监听进程终止信号
- Flutter 桌面窗口关闭时，runtime 会向进程发送 SIGTERM，在此清理 Python pet 子进程

---

### Bug #32: 模型腿部超出窗口 + ProcessSignal.sigterm 在 Windows 不触发

**日期**: 2026-05-13

**现象**:
1. 桌宠模型下半身（腿部）仍然超出窗口不可见
2. 关闭 Flutter 主窗口后 Python 桌宠子进程仍然在运行

**根因**:
1. `pet.html` 使用百分比定位 `model.y = modelY_pct * height`，Live2D chibi 模型的视觉中心
   与几何中心不匹配，42% 仍不够。AUAK 使用硬编码居中 `model.y = innerHeight / 2` 完美居中。
2. `ProcessSignal.sigterm.watch()` 在 Windows 桌面应用关闭时不触发 —
   Windows 通过 WM_CLOSE 销毁窗口而非常规 Unix 信号流程，Dart 进程直接终止。

**修复**:

| # | 问题 | 文件 | 变更 |
|---|------|------|------|
| B32a | 模型偏下 | `assets/live2d/pet.html` | `updateModelTransform()` 改用硬编码居中：`model.x = innerWidth/2; model.y = innerHeight/2` |
| | | `assets/live2d/pet.html` | 自动缩放 90% → 80%（匹配 AUAK） |
| B32b | 进程残留 | `lib/services/live2d_pet.py` | 新增 `ParentAliveChecker` 类：QTimer 每 3s poll Flutter Live2DServer (port 48888) |
| | | `lib/services/live2d_pet.py` | 连续 3 次连接失败 → `self.shutdown()` 自动退出 |
| | | `lib/main.dart` | 保留 `ProcessSignal.sigterm.watch()` 作为额外兜底（macOS/Linux 可用） |

---

### Bug #33: 桌宠启动几秒后自动关闭 — Live2DServer 无 /health 路由

**日期**: 2026-05-13

**现象**: 桌宠打开几秒后自动关闭，Flutter 主窗口并未退出。

**根因**: `ParentAliveChecker` 每 3 秒 poll `http://127.0.0.1:48888`（HEAD 请求），
但 `Live2DServer` 没有 `/` 或 `/health` 路由。它对所有请求尝试从文件系统读取，
`D:\AiVtuber_Agent_profile\` 是目录而非文件 → 500 错误。
Python `urllib.request.urlopen()` 对非 2xx 响应抛出 `HTTPError`，
被 `except Exception` 捕获 → `fail_count++` → 连续 3 次后误判为"Flutter 已退出" → 自动关闭。

**修复**: `lib/services/live2d_server.dart`
- 在 `_handleRequest()` 开头新增 `/` 和 `/health` 路由
- 返回 `200 {"status":"ok"}` → `ParentAliveChecker` 正确识别服务器存活
