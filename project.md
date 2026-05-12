# AI VTuber Agent (Agent × AI VTuber)

## Agent 快速导航

如果你是 AI Agent 接手这个项目，请按顺序阅读：
1. 项目架构 → 了解技术栈和目录结构
2. 环境与启动 → 如何跑起来
3. 数据流 → 前后端如何通信
4. 关键文件索引 → 每个文件做什么
5. 扩展指南 → 常见修改怎么做
6. 开发路线图 → 当前进度和未来目标

---

## 项目架构

```
┌──────────────────────────────────────────────────────────────────┐
│                    AI VTuber Agent (Flutter Desktop)              │
│                                                                   │
│  ┌─────────┐  ┌──────────┐  ┌─────────┐  ┌──────────────────┐   │
│  │  Chat   │  │Character │  │  TTS    │  │  Vision/Memory   │   │
│  │ Screen  │  │ Screen   │  │ Screen  │  │  Screens         │   │
│  └────┬────┘  └────┬─────┘  └────┬────┘  └────────┬─────────┘   │
│       │            │             │                  │             │
│  ┌────┴────────────┴─────────────┴──────────────────┴──────┐     │
│  │              Provider Layer (ChangeNotifier)             │     │
│  │   ChatProvider  │  SettingsProvider                     │     │
│  └──────────────────────┬──────────────────────────────────┘     │
│                         │                                        │
│  ┌──────────────────────┴──────────────────────────────────┐     │
│  │              BackendService (Dart — 进程内)              │     │
│  │  LLMService  │  TTSService  │  MemoryService            │     │
│  │  StorageService  │  VisionService                       │     │
│  └──────────────────────┬──────────────────────────────────┘     │
│                         │ 本地文件 I/O                           │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│              D:\AiVtuber_Agent_profile\ (本地存储)                │
│                                                                  │
│  settings.json  ← LLM 配置、TTS 语音、角色设置                    │
│  sessions\      ← 聊天会话 JSON 文件 ({uuid}.json)                │
│  tts_cache\     ← TTS 音频缓存                                   │
│  screenshots\   ← 截图缓存                                       │
└─────────────────────────────────────────────────────────────────┘
```

**技术栈：**
- **Frontend:** Flutter Desktop (Windows .exe) + Provider state management
- **Window:** bitsdojo_window (frameless native buttons) + flutter_acrylic (Mica 毛玻璃)
- **UI:** fluent_ui (Microsoft Fluent Design System — NavigationView 侧边栏)
- **Backend:** 自包含 Dart 服务层（BackendService），无外部 Python 依赖
- **LLM:** 直接调用 OpenAI 兼容 API（SiliconFlow, OpenRouter, Anthropic, Google, Ollama）
- **TTS:** edge-tts CLI（子进程） + 本地音频缓存
- **Storage:** `D:\\AiVtuber_Agent_profile\\`（Steam 风格本地存档，可备份到云端）

**重要：本项目完全独立，不修改或依赖 D:\\LocalAIVtuber2**

---

## 目录结构

```
AiVtuber_Agent/
├── project.md                          ★ 项目架构文档（本文件）
├── pubspec.yaml                        ★ Flutter 依赖配置
├── analysis_options.yaml                Lint 规则
├── .gitignore                          Git 忽略规则
├── README.md                           项目说明
│
├── assets/                             静态资源（Live2D 模型、音频等）
│   ├── .gitkeep
│   └── live2d/                         ★ Live2D Cubism SDK + 渲染页面
│       ├── pixi.min.js                 PixiJS v6.5.10 (WebGL 渲染)
│       ├── live2d.min.js               Cubism 2.1 Framework
│       ├── live2dcubismcore.min.js     Cubism Core
│       ├── cubism4.min.js              pixi-live2d-display (Cubism 4 封装)
│       └── renderer.html               ★ PixiJS WebGL 渲染页面 + 眼球追踪 + 对话框
│
├── lib/                                Flutter 应用源代码
│   ├── main.dart                       ★ 入口：初始化 Provider + 分支主窗/悬浮窗
│   ├── overlay_main.dart               ★ 悬浮窗独立入口（desktop pet 子窗口）
│   ├── app.dart                        ★ MaterialApp：暗色主题配置
│   │
│   ├── models/                         数据模型
│   │   ├── message.dart                HistoryItem（聊天记录）, Session（会话）
│   │   ├── task.dart                   Task, TaskStatus, TaskResponse（流水线任务）
│   │   └── settings.dart               AppSettings（全部设置项，含 JSON 序列化）
│   │
│   ├── providers/                      状态管理（ChangeNotifier）
│   │   ├── chat_provider.dart          ★ ChatProvider：聊天消息、LLM 流式、会话、Pipeline 集成
│   │   └── settings_provider.dart      SettingsProvider：本地加载/保存设置
│   │
│   ├── services/                       业务逻辑层（BackendService + 子服务）
│   │   ├── backend_service.dart        ★ BackendService：总入口，替换原 ApiClient
│   │   ├── storage_service.dart        ★ StorageService：D:\\AiVtuber_Agent_profile\\ JSON 读写
│   │   ├── llm_service.dart            ★ LLMService：直接调用 OpenAI 兼容 API（SSE 流式）
│   │   ├── tts_service.dart            ★ TTSService：edge-tts 子进程合成 + 缓存
│   │   ├── memory_service.dart         ★ MemoryService：本地关键词匹配记忆检索
│   │   ├── vision_service.dart         ★ VisionService：mss 截图 + easyocr OCR
│   │   ├── live2d_model_service.dart   ★ Live2DModelService：模型文件管理
│   │   ├── live2d_server.dart          ★ Live2DServer：全局 HTTP 文件服务
│   │   ├── pipeline_manager.dart       PipelineManager：Task 流水线（LLM→TTS→Audio）
│   │   └── session_manager.dart        SessionManager：会话 CRUD 操作
│   │
│   ├── screens/                        页面（侧边栏导航）
│   │   ├── home_screen.dart            ★ 主框架：侧边栏 + 页面路由
│   │   ├── chat_screen.dart            ★ 聊天页面：消息列表 + 输入框
│   │   ├── llm_screen.dart             LLM 设置：System Prompt、API Relay 配置
│   │   ├── character_screen.dart       角色设置：Live2D/VRM 切换、位置调整
│   │   ├── tts_screen.dart             TTS 设置：引擎选择、RVC 参数
│   │   ├── vision_screen.dart          视觉：截图 + OCR + Caption
│   │   ├── memory_screen.dart          记忆：会话列表、记忆检索开关
│   │   ├── stream_screen.dart          直播：YouTube 聊天、Setlist
│   │   ├── settings_screen.dart        通用设置：关于、数据路径
│   │   └── pipeline_monitor_screen.dart Pipeline 实时监控
│   │
│   └── widgets/                        可复用组件
│       ├── app_sidebar.dart            侧边栏导航（图标 + Tooltip）
│       ├── api_sidebar.dart            ★ API 设置右侧栏（Base URL / API Key / Model）
│       ├── chat_bubble.dart            聊天气泡（用户/AI 双色）
│       ├── chat_input.dart             聊天输入框（含发送按钮）
│       └── live2d_view.dart            ★ Live2D WebView 渲染组件（Dart↔JS 桥）
│
└── windows/                            Windows 平台原生配置
    ├── CMakeLists.txt                  CMake 构建配置
    └── runner/
        ├── main.cpp                    ★ WinMain 入口
        ├── flutter_window.h/cpp        Flutter 窗口管理
        ├── win32_window.h/cpp          Win32 基础窗口
        ├── utils.h/cpp                 UTF-16 转换工具
        └── resource.h                  Icon 资源 ID
```

---

## 环境与启动

### 前置条件
- Windows 10/11
- Flutter SDK 3.x（`/mnt/d/flutter/bin/flutter`）
- edge-tts（可选，用于 TTS）: `pip install edge-tts`
- Python + easyocr + mss（可选，用于截图 OCR）

### 编译 & 运行

```bash
# 在 Windows 终端（非 WSL）：
cd D:\AiVtuber_Agent

# 安装依赖
flutter pub get

# 运行（Debug 模式）
flutter run -d windows

# 构建 Release (.exe)
flutter build windows
# 输出: build\windows\x64\runner\Release\ai_vtuber_agent.exe
```

### 配置

首次启动后，在 **LLM Settings** 页面配置 API Relay：
- Base URL: `https://api.siliconflow.cn/v1`（或其他 OpenAI 兼容 API）
- API Key: 你的 API 密钥
- Model: `deepseek-ai/DeepSeek-V3.2` 或其他模型

设置自动保存到 `D:\AiVtuber_Agent_profile\settings.json`

### 无后端依赖

本项目 **不需要** 启动任何外部服务器。所有功能运行在进程内：
- LLM 对话 → 直接 HTTP 调用云端 API
- TTS 合成 → edge-tts 子进程
- 数据存储 → `D:\AiVtuber_Agent_profile\` 本地 JSON 文件
- 记忆检索 → 关键字匹配会话文件

---

## 数据流

### 消息发送流程（进程内直接调用）

```
用户在 ChatInput 输入 → 点击发送
  │
  ▼
ChatProvider.sendMessage()
  ├─ 查询 Memory: backend.queryMemory(text) → MemoryService 关键字匹配
  ├─ 组装 SystemPrompt: Vision + OCR + Memory + Instructions
  ├─ 创建会话（若需要）: sessionManager.createNewSession() → StorageService
  ├─ 流式 LLM: backend.completionStream() → LLMService SSE 直连 API
  │   └─ 逐 chunk 更新 UI → _messages.add(assistant msg)
  ├─ 句子分块 → PipelineManager.addLLMResponse() → TTS pipeline
  └─ 保存会话: sessionManager.updateSessionContent() → StorageService
```

### Pipeline 流水线（LLM → TTS → Audio）

```
Task: created
  │
  ▼ LLM streaming
Task: llm_started → llm_finished
  │ 每句完成后 → PipelineManager.addTTSAudio()
  ▼
Task: tts_finished (all audio generated)
  │
  ▼ Audio playback
Task: task_finished (all playback done)
```

### 后端服务调用链（无 HTTP 开销）

| 操作 | 调用链 |
|------|--------|
| 获取设置 | BackendService.getSettings() → StorageService.loadSettings() |
| 保存设置 | BackendService.updateSettings() → StorageService.saveSettings() |
| 流式 LLM | BackendService.completionStream() → LLMService (HTTP SSE) |
| TTS 合成 | BackendService.ttsSynthesize() → TTSService (edge-tts 子进程) |
| 记忆检索 | BackendService.queryMemory() → MemoryService (关键字匹配) |
| 截图 OCR | BackendService.captureScreenshot() → VisionService (mss + easyocr) |
| 会话 CRUD | BackendService.createSession/updateSession/... → StorageService |

---

## 关键文件索引

| 需要修改... | 去这里 |
|-------------|--------|
| 聊天消息逻辑 | lib/providers/chat_provider.dart |
| LLM API 调用 | lib/services/llm_service.dart |
| 设置加载/保存 | lib/services/storage_service.dart |
| TTS 合成 | lib/services/tts_service.dart |
| 记忆检索 | lib/services/memory_service.dart |
| 截图 OCR | lib/services/vision_service.dart |
| Live2D 模型管理 | lib/services/live2d_model_service.dart |
| Live2D 渲染 | lib/widgets/live2d_view.dart → assets/live2d/renderer.html |
| Pipeline 任务状态 | lib/services/pipeline_manager.dart |
| 会话存储 | lib/services/session_manager.dart → storage_service.dart |
| 数据模型（Message） | lib/models/message.dart |
| 数据模型（Task） | lib/models/task.dart |
| 设置项 | lib/models/settings.dart |
| 聊天 UI | lib/screens/chat_screen.dart |
| 聊天气泡 | lib/widgets/chat_bubble.dart |
| 侧边栏导航 | lib/widgets/app_sidebar.dart |
| LLM 设置页 | lib/screens/llm_screen.dart |
| 角色设置页 | lib/screens/character_screen.dart |
| TTS 设置页 | lib/screens/tts_screen.dart |
| 视觉设置页 | lib/screens/vision_screen.dart |
| 记忆页面 | lib/screens/memory_screen.dart |
| 直播页面 | lib/screens/stream_screen.dart |
| 通用设置页 | lib/screens/settings_screen.dart |
| Windows 原生配置 | windows/runner/* |
| 暗色主题 | lib/app.dart |

---

## 扩展指南

### 添加 Live2D 渲染
1. 使用 Flutter WebView 嵌入 PixiJS + Live2D Cubism SDK
2. 模型文件存储在 `D:\AiVtuber_Agent_profile\models\live2d\`
3. 渲染页面: `assets/live2d/renderer.html`
4. Dart↔JS 通信: JavaScript Handler 双向桥

### 添加新的 LLM Provider
1. `lib/services/llm_service.dart` — 添加新的 API 格式适配
2. `lib/screens/llm_screen.dart` — 添加 provider 选择 UI

### 添加新的 TTS 引擎
1. `lib/services/tts_service.dart` — 添加新引擎的合成方法
2. `lib/screens/tts_screen.dart` — 添加引擎选择 UI

### 添加新的设置页
1. `lib/screens/` 下新建 `xxx_screen.dart`
2. `lib/screens/home_screen.dart` 的 `_pages` map 中添加路由
3. `lib/widgets/app_sidebar.dart` 添加新 key

### 添加 Live2D 渲染
1. 研究 `pixi-live2d-display` 的 Flutter 替代方案
2. 使用 Flutter WebView 嵌入 Live2D SDK 或直接使用 Cubism Native SDK
3. 在 `lib/screens/character_screen.dart` 替换占位容器

### 添加 WebSocket 实时通信（未来）
1. `pubspec.yaml` 已包含 `web_socket_channel`
2. 在 `lib/services/` 新建 `ws_service.dart`
3. `lib/providers/chat_provider.dart` 可替换 HTTP 流为 WS 事件流

### 数据备份
- 所有数据在 `D:\AiVtuber_Agent_profile\`
- 可手动复制到云盘 / Git / 备份工具
- 未来可添加自动云端同步

---

## 开发路线图

### Phase 1: 复现 LocalAIVtuber2 核心功能（当前阶段）
- [x] ✅ 项目结构搭建（Flutter Desktop）
- [x] ✅ 数据模型（Message, Task, Settings）
- [x] ✅ Provider 状态管理（ChatProvider, SettingsProvider）
- [x] ✅ BackendService 自包含 Dart 后端（替代 ApiClient HTTP 依赖）
- [x] ✅ LLMService 直连 OpenAI 兼容 API（SSE 流式）
- [x] ✅ TTSService edge-tts 子进程合成
- [x] ✅ MemoryService 本地关键字匹配
- [x] ✅ StorageService D:\AiVtuber_Agent_profile\ JSON 存储
- [x] ✅ VisionService 截图 + OCR
- [x] ✅ PipelineManager 流水线逻辑
- [x] ✅ SessionManager 会话管理
- [x] ✅ 侧边栏导航（10 页面）
- [x] ✅ 聊天界面（流式 LLM 响应）
- [x] ✅ LLM 设置页（System Prompt, API Relay）
- [x] ✅ 角色设置页（Live2D/VRM 切换）
- [x] ✅ TTS 设置页（GPT-SoVITS, RVC）
- [x] ✅ 视觉设置页（截图 OCR）
- [x] ✅ 记忆页面（会话管理）
- [x] ✅ 直播设置页（YouTube 聊天）
- [x] ✅ Pipeline Monitor（实时流水线任务状态）
- [x] ✅ 通用设置页
- [x] ✅ Windows 原生配置（CMake, runner）
- [x] ✅ Git 仓库初始化 + GitHub 推送
- [x] ✅ Bug 修复（memory regex / profileDir 私有访问 / updateBackendUrl / 窗口圆角）
- [x] ✅ Windows 11 原生圆角（DWMWA_WINDOW_CORNER_PREFERENCE）
- [x] ✅ 自定义标题栏（window_manager TitleBarStyle.hidden + Flutter 拖拽栏）
- [x] ✅ 窗口圆角 overlay 修复（WS_THICKFRAME 保留 + DwmExtendFrameIntoClientArea）
- [x] ✅ 标题栏文字下划线修复
- [x] ✅ 聊天页面 API 设置侧边栏（Base URL + API Key + Model + Test Connection）
- [x] ✅ 编译验证 & 运行成功（Windows 11）
- [x] ✅ SystemPrompt 同步到对话（ChatProvider 每次发消息前加载 settings）
- [x] ✅ 启动自动恢复上次会话（SharedPreferences 记录 last_session_id）
- [x] ✅ UI 现代化改造：bitsdojo_window + flutter_acrylic（Mica 毛玻璃）
- [x] ✅ 退回 Material3（移除 fluent_ui 依赖 — API 不稳定）
- [x] ✅ 真正四角圆端：BDW_CUSTOM_FRAME frameless → DWM 自动圆角 + ClipRRect 内容圆角
- [x] ✅ Flutter pub get + 编译验证（需 Windows 终端，WSL 环境受限）
- [x] ✅ Live2D 角色渲染集成（WebView + PixiJS + Cubism SDK）
- [x] ✅ Live2D 桌宠悬浮窗（桌面透明窗口 + 眼球追踪 + 右键对话）
- [ ] ⬜ TTS 音频播放集成
- [ ] ⬜ 端到端测试（聊天 + 记忆 + 截图）

### Phase 2: Agent × AI VTuber（subagent 多 Agent 协作）
- [ ] ⬜ WebSocket 实时双向通信
- [ ] ⬜ SubAgent 编排系统（multi-agent collaboration）
- [ ] ⬜ 上下文压缩（context compression）
- [ ] ⬜ 多 AI Provider（OpenAI, Anthropic, Google, Ollama）
- [ ] ⬜ Agent 任务委派（delegate_task）
- [ ] ⬜ 文件传输（带 SHA256 校验）
- [ ] ⬜ CronJob 定时任务调度

### Phase 3: 增强功能
- [ ] ⬜ 语音输入（VAD + whisper STT）
- [ ] ⬜ 实时 Live2D 嘴型同步
- [ ] ⬜ Android/iOS 平台适配
- [ ] ⬜ Web 端支持

---

## Git 仓库

- **Remote:** `https://github.com/AuthourAkson/AI_Vtuber_Agenty.git`
- **Branch:** `main`
- **推送时机:** 每次完成阶段性功能后更新 project.md 并推送

---

*此文档由 Hermes Agent 维护。*
*项目完全自包含，不依赖 LocalAIVtuber2 后端。*
*数据存储路径：D:\AiVtuber_Agent_profile\（Steam 风格本地存档）*

---

## 最终变更汇总 (2026-05-11)

### Bug 修复
| # | 问题 | 文件 |
|---|------|------|
| B6 | window_manager API 变更 maximizeOrRestore | lib/app.dart |
| B7 | DWM 类型转换 static_cast | windows/runner/flutter_window.cpp |
| B8 | InkWell 缺少 Material 祖先 | lib/app.dart |
| B9 | RenderFlex 溢出（级联） | 自动修复 |
| B10 | DWM 圆角未生效（初始修复） | flutter_window.cpp |
| B11 | overlay + 四角矩形（不完整修复） | flutter_window.cpp |
| B12 | 标题栏下划线 | lib/app.dart |
| B13 | ChatProvider LLMService 未同步 API 设置 | lib/providers/chat_provider.dart |
| B14 | SystemPrompt 未同步到对话 | lib/providers/chat_provider.dart |
| B15 | 启动未自动恢复上次会话 | chat_provider.dart + home_screen.dart |
| B16 | C4819 MSVC 编码警告 | CMakeLists.txt + 源文件 |

### 功能新增
| 功能 | 文件 |
|------|------|
| 聊天页 API 侧边栏（Base URL/Key/Model + Test + Presets） | lib/widgets/api_sidebar.dart（新） |
| 启动自动加载上次对话历史 | lib/providers/chat_provider.dart |
| LLM 侧边栏入口 | lib/widgets/app_sidebar.dart |

### UI 现代化
| 改动 | 说明 |
|------|------|
| window_manager → bitsdojo_window | 原生窗口按钮 + frameless |
| + flutter_acrylic | Windows 11 Mica 毛玻璃效果 |
| + bitsdojo_window_configure(BDW_CUSTOM_FRAME) | main.cpp — 触发 DWM 自动圆角 |
| + ClipRRect(r=12) | app.dart — 内容区圆角 |
| fluent_ui → Material3 | 回退（fluent_ui API 不稳定） |

### 技术栈（最终）
```
Material3 + bitsdojo_window + flutter_acrylic
  ↓
Frameless Window → DWM 自动圆角 + Mica 毛玻璃 + 原生窗口按钮
```

### Live2D 渲染栈 (2026-05-11)
```
Flutter InAppWebView (Edge WebView2)
  ↓
PixiJS v6.5.10 (WebGL)
  ├── pixi-live2d-display v0.4.0 (Cubism 4)
  ├── live2dcubismcore.min.js (Cubism Core)
  └── live2d.min.js (Cubism 2.1 compat)
  ↓
模型文件: D:\AiVtuber_Agent_profile\models\live2d\
```

### 新增文件 (Live2D 集成)
| 文件 | 说明 |
|------|------|
| `assets/live2d/renderer.html` | PixiJS WebGL 渲染页面，含右鍵對話框 UI |
| `assets/live2d/live2dcubismcore.min.js` | Live2D Cubism Core (從 LocalAIVtuber2 複製) |
| `assets/live2d/live2d.min.js` | Live2D Cubism 2.1 Framework |
| `lib/services/live2d_model_service.dart` | 模型匯入/列表/刪除 |
| `lib/widgets/live2d_view.dart` | InAppWebView 封裝 + JavaScript Handler 雙向橋 |

### 修改文件 (Live2D 集成)
| 文件 | 變更 |
|------|------|
| `pubspec.yaml` | + flutter_inappwebview, + desktop_multi_window, + assets/live2d/ |
| `lib/screens/character_screen.dart` | 完整重寫：Live2D 預覽 + 模型選擇 + 文件上傳 |
| `lib/services/backend_service.dart` | + Live2DModelService, 替換 stub 為真實實現 |

### 编译 & 运行
```bash
cd D:\AiVtuber_Agent
flutter clean
flutter pub get
flutter run -d windows
```

---

## 变更汇总 (2026-05-12)

### 桌宠悬浮窗 + 眼球追踪
| 文件 | 说明 |
|------|------|
| `lib/services/live2d_server.dart` | **新增** 全局 HTTP 服务器（localhost:48888），服务 assets + 模型文件 |
| `lib/overlay_main.dart` | **新增** 悬浮窗独立入口，WebView 渲染 Live2D 桌宠 |
| `lib/main.dart` | 分支主窗口/悬浮窗 + 启动 Live2DServer |
| `assets/live2d/renderer.html` | **重写** 加入眼球追踪(ParamEyeBallX/Y)、嘴型同步(ParamMouthOpenY)、右键对话 |
| `assets/live2d/pixi.min.js` | **新增** PixiJS v6.5.10 本地化 |
| `assets/live2d/cubism4.min.js` | **新增** pixi-live2d-display 本地化 |
| `lib/screens/character_screen.dart` | +Launch Desktop Pet 按钮 + 表情/嘴型测试控件 |
| `lib/widgets/live2d_view.dart` | 重构使用共享 Live2DServer |
| `pubspec.yaml` | + window_manager, + desktop_multi_window |

### 架构
```
主窗口 (AI VTuber Agent)              悬浮窗 (Live2D Desktop Pet)
┌──────────────────────┐              ┌─────────────────────┐
│ Character Settings   │   Window     │ 透明 + always-on-top │
│  预览 / 上传 / 控制  │◄─Channel──►│ WebView              │
│  Launch Desktop Pet  │              │  👀 眼球追踪鼠标     │
│  Smile / Star Eyes   │              │  🗣 嘴型同步 (TTS)   │
│  Test Mouth Open     │              │  💬 右键→透明对话框  │
└──────────────────────┘              └─────────────────────┘
              │                                  │
              └──── Live2DServer :48888 ─────────┘
                     (HTTP 文件服务)
```

### Bug 修复 (第三批次)
| # | 问题 | 文件 |
|---|------|------|
| B17 | file_picker v11 API 变更 | character_screen.dart |
| B18 | WebView file:// CORS 模型加载失败 | live2d_view.dart → Live2DServer |
| B19 | 中文路径 URL 编码 → 404 | live2d_server.dart (Uri.decodeComponent) |
| B20 | desktop_multi_window API (WindowController) | character_screen.dart, overlay_main.dart |
| B21 | cubism4.min.js 加载顺序 → PIXI.live2d undefined | renderer.html |
| B22 | window_manager 在子窗口不可用 | overlay_main.dart |

---
---
## 变更汇总 (2026-05-12 晚 — VTube Studio 风格透明浮窗)

### 架构重构：从全屏覆盖到独立透明窗口

**旧方案 (PetModeOverlay)**：全屏透明 Flutter 路由覆盖在主窗口上，阻断 UI 交互和窗口拖拽。

**新方案 (Native WebView2 Overlay)**：C++ 原生 Win32 窗口，独立于 Flutter 主窗口，VTube Studio 风格：

```
主窗口 (AI VTuber Agent)              独立透明浮窗 (Live2D Overlay)
┌──────────────────────────┐         ┌─────────────────────┐
│  正常 UI                 │         │ WS_EX_LAYERED       │
│  (Chat/Settings/...)     │  FFI    │ WS_EX_TOPMOST       │
│                          │◄───────►│ WS_EX_TOOLWINDOW    │
│  Character Settings:     │         │                     │
│    [Open Overlay]        │         │  WebView2 (透明BG)  │
│    [Close] [Toggle Top]  │         │  PixiJS + Live2D    │
│                          │         │  👀 眼球追踪鼠标     │
└──── Live2DServer :48888 ─┴─────────┤  ✋ 拖拽移动窗口     │
                                     │  ↕↔ 边缘调整大小    │
                                     └─────────────────────┘
                                              ↕ OBS 捕获
```

### 新增/修改文件

| 文件 | 说明 |
|------|------|
| `windows/runner/live2d_overlay_window.h` | **新增** C++ 透明窗口类：Win32 + WebView2 + DWM 合成 |
| `windows/runner/live2d_overlay_window.cpp` | **新增** 实现：窗口创建、WebView2 初始化、拖拽/缩放、透明背景 |
| `windows/runner/live2d_overlay_bridge.cpp` | **新增** C API 桥接（Dart FFI 调用入口） |
| `windows/runner/CMakeLists.txt` | **修改** + overlay 源文件 + WebView2 SDK 链接 |
| `lib/services/live2d_overlay_ffi.dart` | **新增** Dart FFI 绑定：create/destroy/move/resize/navigate/setTopMost |
| `lib/main.dart` | **修改** + Live2DOverlayFfi 初始化 |
| `lib/screens/character_screen.dart` | **重写** PetModeOverlay → Native Overlay：Open/Close/Toggle Topmost 按钮 |
| `assets/live2d/renderer.html` | **修改** + 查询参数解析 (?model=&x=&y=&scale=), + 透明背景 !important |
| `lib/widgets/pet_mode_overlay.dart` | **删除**（已废弃） |

### 技术细节

**透明窗口实现：**
- `WS_EX_LAYERED` | `WS_EX_TOPMOST` | `WS_EX_TOOLWINDOW` — 分层 + 置顶 + 无任务栏图标
- `DwmExtendFrameIntoClientArea` (margins=-1) — DWM 全窗口玻璃效果
- `DwmEnableBlurBehindWindow` — 启用模糊透明
- `ICoreWebView2Controller2::put_DefaultBackgroundColor({0,0,0,0})` — WebView 透明

**窗口交互：**
- `WM_NCHITTEST` 返回 `HTCAPTION` — 点击模型本体拖拽整个窗口
- 边缘 8px 检测 — 四边 + 四角调整窗口大小
- `ESC` 键关闭窗口

**WebView2 编译：**
- 复用 flutter_inappwebview 的 WebView2 SDK (build/windows/x64/packages/)
- 链接 WebView2LoaderStatic.lib (静态库，无需额外 DLL)
- 覆盖 `_HAS_EXCEPTIONS` 宏（WebView2 COM 回调需要）

### 移除的旧方案

| 旧文件 | 状态 |
|--------|------|
| `lib/widgets/pet_mode_overlay.dart` | **删除** — 全屏覆盖阻断主窗口 |
| `lib/overlay_main.dart` | 保留但不再使用（desktop_multi_window 方案） |

### 后续优化

- [ ] 从 Dart 调用 JS 控制模型（通过 WebView2 WebMessage API）
- [ ] 鼠标点击穿透模式（OBS 捕获时不阻挡操作）
- [ ] 窗口位置/大小持久化
- [ ] 多显示器支持

### Bug 修复 (第五批次)

| # | 问题 | 修复 |
|---|------|------|
| B26 | PetModeOverlay 覆盖全屏阻断主窗口 UI | → Native WebView2 overlay 窗口 |
| B27 | PetModeOverlay 导致主窗口无法拖拽 | → 独立 Win32 窗口 (WS_EX_TOOLWINDOW) |
| B28 | desktop_multi_window 子窗口 flutter_inappwebview 插件未注册 | → 绕过 Flutter 插件，直接用 C++ WebView2 |
| B29 | CMake WebView2 SDK 路径错误 `CMAKE_SOURCE_DIR/build` → `../build` | CMakeLists.txt 路径修复 + fallback |
