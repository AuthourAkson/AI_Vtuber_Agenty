# AI VTuber Agent — Bug Tracker

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

**待修复**:

D:\AiVtuber_Agent> flutter run -d windows
Launching lib\main.dart on Windows in debug mode...
CMake Warning (dev) at flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/windows/CMakeLists.txt:31 (add_custom_command):
  The following keywords are not supported when using
  add_custom_command(TARGET): DEPENDS.

  Policy CMP0175 is not set: add_custom_command() rejects invalid arguments.
  Run "cmake --help-policy CMP0175" for policy details.  Use the cmake_policy
  command to set the policy and suppress this warning.
This warning is for project developers.  Use -Wno-dev to suppress it.

lib/services/wenzagent_service.dart(175,15): error GE5CFE876: The method 'markMessagesAsRead' isn't defined for the type 'CachedAgentProxy'. [D:\AiVtuber_Agent\build\windows\x64\flutter\flutter_assemble.vcxproj]
D:\Microsoft Visual Studio\2022\BuildTools\MSBuild\Microsoft\VC\v170\Microsoft.CppCommon.targets(254,5): error MSB8066: “D:\AiVtuber_Agent\build\windows\x64\CMakeFiles\c34551fe35923833d11a024e38cb5a47\flutter_windows.dll.rule;D:\AiVtuber_Agent\build\windows\x64\CMakeFiles\d93f91fab4440261b871f34779069aea\flutter_assemble.rule”的自定义生成已退出，代码为 1。 [D:\AiVtuber_Agent\build\windows\x64\flutter\flutter_assemble.vcxproj]
Building Windows application...                                    16.0s
Error: Build process failed.

---

## ✅ 已修复 (2026-05-15)

### Bug #37: WenzAgent 集成构建错误 — 7 个类型/方法不匹配

**日期**: 2026-05-15

**现象**: WenzAgent 多Agent 集成首次构建失败，7 个编译错误：

- `DeviceInfo` / `MultiAgentInfo` 类型在 multi_agent_screen.dart 中不可见
- `CachedAgentProxy.markMessagesAsRead()` 方法签名不匹配（缺少 `readerDeviceId` 参数）
- `LanDeviceInfo` 实际字段为 `id` / `name` 而非 `deviceId` / `deviceName`
- `SessionSummaryEntity` 实际字段为 `lastMsgContent` 而非 `latestMessageContent`，无 `agentStatus` 字段

**根因**: 代码基于 wenzagent 文档（frontend-integration-guide.md）而非实际 API 签名编写。实际 wenzagent SDK 的类字段名称与文档描述不一致。

**修复**:

| #    | 文件                                    | 变更                                                                                      |
| ---- | ------------------------------------- | --------------------------------------------------------------------------------------- |
| B37a | `lib/screens/multi_agent_screen.dart` | 添加 `import '../services/wenzagent_service.dart'` 以引入 `DeviceInfo` / `MultiAgentInfo` 类型 |
| B37b | `lib/services/wenzagent_service.dart` | `markMessagesAsRead()` → `markMessagesAsRead(readerDeviceId: _deviceId)`                |
| B37c | `lib/services/wenzagent_service.dart` | `d.deviceId` → `d.id`，`d.deviceName ?? 'Unknown'` → `d.name ?? 'Unknown'`               |
| B37d | `lib/services/wenzagent_service.dart` | `s.latestMessageContent` → `s.lastMsgContent`，移除不存在的 `agentStatus`，固定为 `'idle'`         |

---

### Bug #37 续: CachedAgentProxy 无 markMessagesAsRead 方法

**现象** (第二次构建):

```
lib/services/wenzagent_service.dart(175,15): error: The method 'markMessagesAsRead' isn't defined
for the type 'CachedAgentProxy'.
```

**根因**: `markMessagesAsRead(readerDeviceId:)` 只存在于底层 `AgentProxy` 类，`CachedAgentProxy` 没有暴露此方法。前端文档说 `proxy.markMessagesAsRead()` 但实际 API 需要通过 DeviceClient 层调用。

**修复**: `wenzagent_service.dart` — 改用 `DeviceClient.markAllMessagesAsRead(employeeId: employeeId)` 替代 `proxy.markMessagesAsRead(readerDeviceId:)`。
