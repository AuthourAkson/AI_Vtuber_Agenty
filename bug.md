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

## ✅ 已修复 (2026-05-14)

### Bug #34: debugFrameWasSentToEngine 断言失败 — 无限重建循环

**日期**: 2026-05-14

**现象**: `flutter run` 启动后立即抛出：

```
Another exception was thrown: 'package:flutter/src/widgets/binding.dart':
Failed assertion: line 1280 pos 16: 'debugFrameWasSentToEngine': is not true.
```

错误不断重复生成，直到关闭终端。

**根因（两个独立问题）**:

1. **IndexedStack 构建全部 10 页面**: `HomeScreen` 使用 `IndexedStack` 同时构建所有 10 个子页面。当任一页面的 `build()` 方法中发生异常时，整个帧管线中断，触发断言。错误会级联——每个子页面的 Consumer 重建都会尝试新帧，再次失败。

2. **手动 AnimationController 链**: `app_sidebar.dart` 和 `side_panel.dart` 使用 `AnimationController` + `Tween` + `CurvedAnimation` + 显式动画 Widget（`AnimatedBuilder` / `SlideTransition`）。这些手动动画链在某些帧时序下与 `SchedulerBinding` 帧调度不同步。

**修复**:

| #   | 文件                             | 变更                                                                    |
| --- | ------------------------------ | --------------------------------------------------------------------- |
| 1   | `lib/screens/home_screen.dart` | `IndexedStack` → 条件 `switch`，每次只构建一个活跃页面                              |
| 2   | `lib/widgets/app_sidebar.dart` | `AnimationController` + `AnimatedBuilder` → `AnimatedContainer`（隐式动画） |
| 3   | `lib/widgets/side_panel.dart`  | `AnimationController` + `SlideTransition` → `AnimatedSlide`（隐式动画）     |

**结果**: 代码中零个 `AnimationController` / `TickerProvider` / `Tween` / `CurvedAnimation`。所有动画由框架隐式动画系统管理。

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

| #    | 问题   | 文件                           | 变更                                                                                 |
| ---- | ---- | ---------------------------- | ---------------------------------------------------------------------------------- |
| B32a | 模型偏下 | `assets/live2d/pet.html`     | `updateModelTransform()` 改用硬编码居中：`model.x = innerWidth/2; model.y = innerHeight/2` |
|      |      | `assets/live2d/pet.html`     | 自动缩放 90% → 80%（匹配 AUAK）                                                            |
| B32b | 进程残留 | `lib/services/live2d_pet.py` | 新增 `ParentAliveChecker` 类：QTimer 每 3s poll Flutter Live2DServer (port 48888)       |
|      |      | `lib/services/live2d_pet.py` | 连续 3 次连接失败 → `self.shutdown()` 自动退出                                                |
|      |      | `lib/main.dart`              | 保留 `ProcessSignal.sigterm.watch()` 作为额外兜底（macOS/Linux 可用）                          |

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

### Bug #35: SidePanel Stack 无界约束 — performLayout 断言失败

**日期**: 2026-05-14

**现象**: 窗口启动后崩溃，`debugFrameWasSentToEngine` 级联：

```
══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞══════════════════
A Stack requires bounded constraints from its parent.
```

**根因**: `Positioned(left: 0, top: 0, bottom: 0)` 只约束了高度，宽度无界 → `Stack` 需要两维都有界。

**修复**: `SidePanel` 的 Stack 包裹在 `SizedBox(width: widget.width)` 中。

---

### Bug #36: Session 面板重叠 AppSidebar + 按钮无响应 + 布局错乱

**日期**: 2026-05-14

**现象**:

1. 左侧会话管理面板关闭时**视觉覆盖** AppSidebar 区域
2. 点击 session 列表的 "New Session" 和会话项**无反应**
3. 左侧侧边栏被 session 面板部分覆盖，但点原本位置仍会切换页面

**根因（多个）**:

1. **无 ClipRect**: `ChatScreen` 的 `Stack` 无裁剪 → `AnimatedSlide(offset: -1.0)` 将面板左移 260px，进入 AppSidebar 的渲染区
2. **Header 按钮代码错误**: `findAncestorStateOfType<_ChatScreenState>()` 查找私有类型 + 空 `setState((){})` — 完全不工作
3. **状态未外露**: `SidePanel` 的 `_isOpen` 是内部状态，外部无法控制
4. **Positioned 无显式 width**: 需 `SizedBox` 包裹提供有界宽度

**待修复**: Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter_markdown/src/builder.dart': Failed assertion: line 267 pos 12:
'_inlines.isEmpty': is not true.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter/src/widgets/framework.dart': Failed assertion: line 6417 pos 14: '() {
Another exception was thrown: 'package:flutter/src/widgets/framework.dart': Failed assertion: line 6268 pos 12:
'_dependents.isEmpty': is not true.
[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: 'package:flutter/src/rendering/object.dart': Failed assertion: line 3536 pos 12: 'attached': is not true.
#0      _AssertionError._doThrowNew (dart:core-patch/errors_patch.dart:67:4)
#1      _AssertionError._throwNew (dart:core-patch/errors_patch.dart:49:5)
#2      RenderObject.getTransformTo (package:flutter/src/rendering/object.dart:3536:12)
#3      RenderBox.localToGlobal (package:flutter/src/rendering/box.dart:3092:39)
#4      _CustomPlatformViewState._reportWidgetPosition (package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart:426:28)
<asynchronous suspension>

Live2D JS: "Live2D %s" "2.1.00_1"
Live2D JS: "profile : Desktop"
Live2D JS: "  [PROFILE_NAME] = Desktop"
Live2D JS: "  [USE_ADJUST_TRANSLATION] = false"
Live2D JS: "  [USE_CACHED_POLYGON_IMAGE] = false"
Live2D JS: "  [EXPAND_W] = 2"
Loading model: http://localhost:48888/models/live2d/Amiya/Amiya.model3.json
Live2D JS: "[CSM][I]Live2D Cubism Core version: 05.00.0000 (83886080)\n"
Live2D JS: "[CSM][I]CubismFramework.startUp() is complete.\n"
Live2D JS: "[CSM][I]CubismFramework.initialize() is complete.\n"
Live2D JS: "Live2D Cubism SDK Core Version 5.0.0"
Loading model: http://localhost:48888/models/live2d/Amiya/Amiya.model3.json
Live2D JS: "Live2D Cubism SDK Core Version 5.0.0"
Another exception was thrown: 'package:flutter/src/widgets/framework.dart': Failed assertion: line 6417 pos 14: '() {
Another exception was thrown: 'package:flutter/src/widgets/framework.dart': Failed assertion: line 6417 pos 14: '() {
Another exception was thrown: 'package:flutter/src/widgets/framework.dart': Failed assertion: line 6417 pos 14: '() {
Another exception was thrown: 'package:flutter/src/widgets/framework.dart': Failed assertion: line 6417 pos 14: '() {
Another exception was thrown: 'package:flutter/src/widgets/framework.dart': Failed assertion: line 6417 pos 14: '() {
Another exception was thrown: 'package:flutter/src/widgets/framework.dart': Failed assertion: line 6417 pos 14: '() {
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: Tried to build dirty widget in the wrong build scope.
Another exception was thrown: 'package:flutter/src/widgets/framework.dart': Failed assertion: line 6417 pos 14: '() {
