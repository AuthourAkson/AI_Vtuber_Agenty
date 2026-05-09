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
- **Backend:** 自包含 Dart 服务层（BackendService），无外部 Python 依赖
- **LLM:** 直接调用 OpenAI 兼容 API（SiliconFlow, OpenRouter, Anthropic, Google, Ollama）
- **TTS:** edge-tts CLI（子进程） + 本地音频缓存
- **Storage:** `D:\AiVtuber_Agent_profile\`（Steam 风格本地存档，可备份到云端）

**重要：本项目完全独立，不修改或依赖 D:\LocalAIVtuber2**

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
│   └── .gitkeep
│
├── lib/                                Flutter 应用源代码
│   ├── main.dart                       ★ 入口：初始化 Provider + WindowManager
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
│   │   ├── storage_service.dart        ★ StorageService：D:\AiVtuber_Agent_profile\ JSON 读写
│   │   ├── llm_service.dart            ★ LLMService：直接调用 OpenAI 兼容 API（SSE 流式）
│   │   ├── tts_service.dart            ★ TTSService：edge-tts 子进程合成 + 缓存
│   │   ├── memory_service.dart         ★ MemoryService：本地关键词匹配记忆检索
│   │   ├── vision_service.dart         ★ VisionService：mss 截图 + easyocr OCR
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
│       ├── chat_bubble.dart            聊天气泡（用户/AI 双色）
│       └── chat_input.dart             聊天输入框（含发送按钮）
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
- [ ] ⬜ Flutter pub get + 编译验证（Windows 终端）
- [ ] ⬜ Live2D 角色渲染集成
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
