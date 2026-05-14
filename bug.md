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

**修复**: `lib/screens/chat_screen.dart`
- 新增 `ClipRect` 包裹 Stack — 面板关闭时裁剪到 ChatScreen 边界内
- 新增 `_SidePanelBuild` 内联组件 — 由 ChatScreen 控制 `isOpen`，不再用内部状态
- Header 按钮 → 直接 `setState(() => _sessionPanelOpen = !_sessionPanelOpen)`
- Header 新增 Settings 齿轮按钮 → toggle 设置面板
- 所有 `Positioned` 的子组件包裹 `SizedBox(width: ...)`
Launching lib\main.dart on Windows in debug mode...
CMake Warning (dev) at flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/windows/CMakeLists.txt:31 (add_custom_command):
  The following keywords are not supported when using
  add_custom_command(TARGET): DEPENDS.

  Policy CMP0175 is not set: add_custom_command() rejects invalid arguments.
  Run "cmake --help-policy CMP0175" for policy details.  Use the cmake_policy
  command to set the policy and suppress this warning.
This warning is for project developers.  Use -Wno-dev to suppress it.

D:\AiVtuber_Agent\windows\flutter\ephemeral\.plugin_symlinks\flutter_inappwebview_windows\windows\utils\base64.cpp(1,1): warning C4819: 该文件包含不能在当前代码页(936)中表示的字符。请将该文件保存为 Unicode 格式以防止数据丢失 [D:\AiVtuber_Agent\build\windows\x64\plugins\flutter_inappwebview_windows\flutter_inappwebview_windows_plugin.vcxproj]
D:\AiVtuber_Agent\windows\flutter\ephemeral\.plugin_symlinks\flutter_inappwebview_windows\windows\types\web_resource_response.cpp(54,28): warning C4244: “参数”: 从“__int64”转换到“int”，可能丢失数据 [D:\AiVtuber_Agent\build\windows\x64\plugins\flutter_inappwebview_windows\flutter_inappwebview_windows_plugin.vcxproj]
D:\AiVtuber_Agent\build\windows\x64\packages\Microsoft.Web.WebView2\build\native\include\WebView2EnvironmentOptions.h(194,3): warning C4458: “value”的声明隐藏了类成员 [D:\AiVtuber_Agent\build\windows\x64\plugins\flutter_inappwebview_windows\flutter_inappwebview_windows_plugin.vcxproj]
D:\AiVtuber_Agent\build\windows\x64\packages\Microsoft.Web.WebView2\build\native\include\WebView2EnvironmentOptions.h(193,3): warning C4458: “value”的声明隐藏了类成员 [D:\AiVtuber_Agent\build\windows\x64\plugins\flutter_inappwebview_windows\flutter_inappwebview_windows_plugin.vcxproj]
D:\AiVtuber_Agent\build\windows\x64\packages\Microsoft.Web.WebView2\build\native\include\WebView2EnvironmentOptions.h(194,3): warning C4458: “value”的声明隐藏了类成员 [D:\AiVtuber_Agent\build\windows\x64\plugins\flutter_inappwebview_windows\flutter_inappwebview_windows_plugin.vcxproj]
D:\AiVtuber_Agent\build\windows\x64\packages\Microsoft.Web.WebView2\build\native\include\WebView2EnvironmentOptions.h(193,3): warning C4458: “value”的声明隐藏了类成员 [D:\AiVtuber_Agent\build\windows\x64\plugins\flutter_inappwebview_windows\flutter_inappwebview_windows_plugin.vcxproj]
Building Windows application...                                   249.3s
√ Built build\windows\x64\runner\Debug\ai_vtuber_agent.exe
Live2D HTTP server on http://localhost:48888
Live2DOverlayFfi: Failed to load native functions: Invalid argument(s): Failed to lookup symbol 'CreateOverlay': None of the loaded modules contained the requested symbol 'CreateOverlay'.
[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: SignalException: Failed to listen for SIGTERM, osError: OS Error: 不支持该请求。, errno = 50

══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═════════════════════════════════════════════════════════
The following assertion was thrown during performLayout():
A Stack requires bounded constraints from its parent. This error commonly occurs when a Stack is
placed inside a widget like Column, ListView, or other widgets that do not constrain their children.
To fix this, wrap the Stack in a widget that provides finite height and width constraints, such as a
SizedBox or ConstrainedBox. Use Expanded only if the parent is a Flex widget like Row or Column.
'package:flutter/src/rendering/stack.dart':
Failed assertion: line 664 pos 7: 'size.isFinite'

Either the assertion indicates an error in the framework itself, or we should provide substantially
more information in this error message to help you determine and fix the underlying cause.
In either case, please report this assertion by filing a bug on GitHub:
  https://github.com/flutter/flutter/issues/new?template=02_bug.yml

The relevant error-causing widget was:
  Stack Stack:file:///D:/AiVtuber_Agent/lib/widgets/side_panel.dart:46:12

When the exception was thrown, this was the stack:
#2      RenderStack._computeSize (package:flutter/src/rendering/stack.dart:664:7)
#3      RenderStack.performLayout (package:flutter/src/rendering/stack.dart:680:12)
#4      RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#5      RenderStack.layoutPositionedChild (package:flutter/src/rendering/stack.dart:549:11)
#6      RenderStack.performLayout (package:flutter/src/rendering/stack.dart:691:13)
#7      RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#8      RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#9      RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#10     ChildLayoutHelper.layoutChild (package:flutter/src/rendering/layout_helper.dart:62:11)
#11     RenderFlex._computeSizes (package:flutter/src/rendering/flex.dart:1275:26)
#12     RenderFlex.performLayout (package:flutter/src/rendering/flex.dart:1329:32)
#13     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#14     ChildLayoutHelper.layoutChild (package:flutter/src/rendering/layout_helper.dart:62:11)
#15     RenderFlex._computeSizes (package:flutter/src/rendering/flex.dart:1275:26)
#16     RenderFlex.performLayout (package:flutter/src/rendering/flex.dart:1329:32)
#17     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#18     MultiChildLayoutDelegate.layoutChild (package:flutter/src/rendering/custom_layout.dart:180:12)
#19     _ScaffoldLayout.performLayout (package:flutter/src/material/scaffold.dart:1113:7)
#20     MultiChildLayoutDelegate._callPerformLayout (package:flutter/src/rendering/custom_layout.dart:246:7)
#21     RenderCustomMultiChildLayoutBox.performLayout (package:flutter/src/rendering/custom_layout.dart:417:14)
#22     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#23     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#24     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#25     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#26     _RenderCustomClip.performLayout (package:flutter/src/rendering/proxy_box.dart:1549:11)
#27     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#28     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#29     _RenderCustomClip.performLayout (package:flutter/src/rendering/proxy_box.dart:1549:11)
#30     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#31     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#32     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#33     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#34     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#35     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#36     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#37     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#38     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#39     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#40     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#41     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#42     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#43     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#44     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#45     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#46     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#47     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#48     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#49     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#50     RenderOffstage.performLayout (package:flutter/src/rendering/proxy_box.dart:3923:13)
#51     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#52     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#53     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#54     _RenderTheaterMixin.layoutChild (package:flutter/src/widgets/overlay.dart:1084:13)
#55     _RenderTheater.performLayout (package:flutter/src/widgets/overlay.dart:1429:9)
#56     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#57     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#58     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#59     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#60     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#61     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#62     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#63     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#64     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#65     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#66     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#67     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#68     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#69     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#70     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#71     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#72     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#73     RenderProxyBoxMixin.performLayout (package:flutter/src/rendering/proxy_box.dart:118:18)
#74     RenderObject.layout (package:flutter/src/rendering/object.dart:2768:7)
#75     RenderView.performLayout (package:flutter/src/rendering/view.dart:292:12)
#76     RenderObject._layoutWithoutResize (package:flutter/src/rendering/object.dart:2616:7)
#77     PipelineOwner.flushLayout (package:flutter/src/rendering/object.dart:1174:18)
#78     PipelineOwner.flushLayout (package:flutter/src/rendering/object.dart:1187:15)
#79     RendererBinding.drawFrame (package:flutter/src/rendering/binding.dart:629:23)
#80     WidgetsBinding.drawFrame (package:flutter/src/widgets/binding.dart:1304:13)
#81     RendererBinding._handlePersistentFrameCallback (package:flutter/src/rendering/binding.dart:495:5)
#82     SchedulerBinding._invokeFrameCallback (package:flutter/src/scheduler/binding.dart:1430:15)
#83     SchedulerBinding.handleDrawFrame (package:flutter/src/scheduler/binding.dart:1345:9)
#84     SchedulerBinding.scheduleWarmUpFrame.<anonymous closure> (package:flutter/src/scheduler/binding.dart:1055:9)
#85     PlatformDispatcher.scheduleWarmUpFrame.<anonymous closure> (dart:ui/platform_dispatcher.dart:906:16)
#89     _RawReceivePort._handleMessage (dart:isolate-patch/isolate_patch.dart:193:12)
(elided 5 frames from class _AssertionError, class _Timer, and dart:async-patch)

The following RenderObject was being processed when the exception was fired: RenderStack#16885 relayoutBoundary=up5
NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE:
  creator: Stack ← SidePanel ← Positioned ← Stack ← Consumer2<ChatProvider, SettingsProvider> ←
    ChatScreen ← ColoredBox ← Container ← Expanded ← Row ← HomeScreen ← Expanded ← ⋯
  parentData: top=0.0; bottom=0.0; left=0.0; offset=Offset(0.0, 0.0) (can use size)
  constraints: BoxConstraints(0.0<=w<=Infinity, h=688.7)
  size: MISSING
  alignment: AlignmentDirectional.topStart
  textDirection: ltr
  fit: loose
  clipBehavior: none
This RenderObject had the following descendants (showing up to depth 5):
    child 1: RenderSemanticsGestureHandler#db2eb NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE
      child: RenderPointerListener#7de0e NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE
        child: RenderConstrainedBox#f5b56 NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE
          child: RenderDecoratedBox#af020 NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE
            child: RenderPadding#b387b NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE
    child 2: RenderFractionalTranslation#9957e NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE
      child: RenderConstrainedBox#2288b NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE
        child: _RenderColoredBox#d4bc2 NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE
          child: RenderFlex#4575d NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE
            child 1: RenderPadding#fbef9 NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE
            child 2: RenderPositionedBox#996f1 NEEDS-LAYOUT NEEDS-PAINT NEEDS-COMPOSITING-BITS-UPDATE
            child 3: RenderConstrainedBox#a1e42 NEEDS-LAYOUT NEEDS-PAINT
════════════════════════════════════════════════════════════════════════════════════════════════════

Another exception was thrown: RenderBox was not laid out: RenderStack#16885 relayoutBoundary=up5 NEEDS-PAINT
NEEDS-COMPOSITING-BITS-UPDATE
Another exception was thrown: 'package:flutter/src/rendering/object.dart': Failed assertion: line 5737 pos 14:
'!childSemantics.renderObject._needsLayout': is not true.
Another exception was thrown: RenderBox was not laid out: RenderStack#16885 relayoutBoundary=up5
Another exception was thrown: 'package:flutter/src/rendering/object.dart': Failed assertion: line 5737 pos 14:
'!childSemantics.renderObject._needsLayout': is not true.
Another exception was thrown: 'package:flutter/src/widgets/binding.dart': Failed assertion: line 1280 pos 16:
'debugFrameWasSentToEngine': is not true.
Another exception was thrown: 'package:flutter/src/widgets/binding.dart': Failed assertion: line 1280 pos 16:
'debugFrameWasSentToEngine': is not true.
Another exception was thrown: 'package:flutter/src/rendering/object.dart': Failed assertion: line 5737 pos 14:
'!childSemantics.renderObject._needsLayout': is not true.
Another exception was thrown: 'package:flutter/src/rendering/object.dart': Failed assertion: line 5493 pos 14:
'!semantics.parentDataDirty': is not true.
Another exception was thrown: 'package:flutter/src/widgets/binding.dart': Failed assertion: line 1280 pos 16:
'debugFrameWasSentToEngine': is not true.
Another exception was thrown: 'package:flutter/src/widgets/binding.dart': Failed assertion: line 1280 pos 16:
'debugFrameWasSentToEngine': is not true.
Another exception was thrown: 'package:flutter/src/widgets/binding.dart': Failed assertion: line 1280 pos 16:
'debugFrameWasSentToEngine': is not true.
Another exception was thrown: 'package:flutter/src/widgets/binding.dart': Failed assertion: line 1280 pos 16:
'debugFrameWasSentToEngine': is not true.
Syncing files to device Windows...                                 170ms

Flutter run key commands.
r Hot reload.
R Hot restart.
h List all available interactive commands.
d Detach (terminate "flutter run" but leave application running).
c Clear the screen
q Quit (terminate the application on the device).

A Dart VM Service on Windows is available at: http://127.0.0.1:54662/sDdqvq9Vwag=/
The Flutter DevTools debugger and profiler on Windows is available at:
http://127.0.0.1:54662/sDdqvq9Vwag=/devtools/?uri=ws://127.0.0.1:54662/sDdqvq9Vwag=/ws
