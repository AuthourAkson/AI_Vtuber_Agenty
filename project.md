# AI VTuber Agent (Agent × AI VTuber)

## Agent 快速导航

如果你是 AI Agent 接手这个项目，请按顺序阅读：
1. 项目架构 → 了解技术栈和目录结构
2. 环境与启动 → 如何跑起来
3. 数据流 → 前后端如何通信（含 WebSocket 计划）
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
│  │              Service Layer                               │     │
│  │   ApiClient  │  PipelineManager  │  SessionManager      │     │
│  └──────────────────────┬──────────────────────────────────┘     │
│                         │ HTTP REST                             │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│              LocalAIVtuber2 Backend (Python FastAPI:8000)         │
│                                                                  │
│  VoiceInput ──▶ Mic → VAD → Whisper → Text                       │
│  VisionInput ─▶ Screen → EasyOCR + BLIP → Text                   │
│  LLM ────────▶ Local llama.cpp OR Remote API → Streaming text    │
│  TTS ────────▶ GPT-SoVITS → Audio waveform                       │
│  Memory ─────▶ Qdrant vector search → Relevant context            │
│  History ────▶ JSON file storage                                  │
│  ChatFetch ──▶ pytchat YouTube API                                │
│                                                                  │
│  RVC Proxy ──▶ /api/rvc/* → RVC server (port 8001)              │
└─────────────────────────────────────────────────────────────────┘
```

**技术栈：**
- **Frontend:** Flutter Desktop (Windows .exe) + Provider state management
- **Backend:** 复用 LocalAIVtuber2 Python FastAPI (localhost:8000)
- **未来规划:** 添加独立后端 + WebSocket + 多 Agent 协作

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
│   │   └── settings_provider.dart      SettingsProvider：从后端加载设置 + 本地持久化
│   │
│   ├── services/                       业务逻辑层
│   │   ├── api_client.dart             ★ ApiClient：所有后端 HTTP 请求（REST API 封装）
│   │   ├── pipeline_manager.dart       PipelineManager：Task 流水线（LLM→TTS→Audio）
│   │   └── session_manager.dart        SessionManager：会话 CRUD 操作
│   │
│   ├── screens/                        页面（对应 LAV2 侧边栏导航）
│   │   ├── home_screen.dart            ★ 主框架：侧边栏 + 页面路由
│   │   ├── chat_screen.dart            ★ 聊天页面：消息列表 + 输入框
│   │   ├── llm_screen.dart             LLM 设置：System Prompt、API Relay 配置
│   │   ├── character_screen.dart       角色设置：Live2D/VRM 切换、位置调整
│   │   ├── tts_screen.dart             TTS 设置：引擎选择、RVC 参数
│   │   ├── vision_screen.dart          视觉：截图 + OCR + Caption
│   │   ├── memory_screen.dart          记忆：会话列表、记忆检索开关
│   │   ├── stream_screen.dart          直播：YouTube 聊天、Setlist
│   │   └── settings_screen.dart        通用设置：服务器连接、关于
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
- Windows 10/11（目标是生成 .exe）
- Flutter SDK 3.x（安装在工作站上，WSL 中为 `/mnt/d/flutter/bin/flutter`）
- LocalAIVtuber2 后端运行中（`localhost:8000`）

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

### 后端依赖

本应用依赖 LocalAIVtuber2 后端。启动后端：

```bash
cd D:\LocalAIVtuber2\backend
.\\venv\\Scripts\\activate
python server.py
# 后端运行在 http://localhost:8000
```

### WSL 注意事项
- Flutter SDK 在 WSL 的 `/mnt/d/flutter/` 下
- `flutter --version` 在 WSL 中可能超时（跨文件系统性能问题）
- 推荐在 Windows 原生终端使用 Flutter 命令
- 若要从 WSL 使用 Flutter：先修复 CRLF 问题
  ```bash
  find /mnt/d/flutter/bin -name "*.sh" -exec sed -i 's/\r$//' {} \;
  ```

---

## 数据流

### 消息发送流程（当前：HTTP REST）

```
用户在 ChatInput 输入 → 点击发送
  │
  ▼
ChatProvider.sendMessage()
  ├─ 查询 Memory: ApiClient.queryMemory(text) → POST /api/memory/context
  ├─ 组装 SystemPrompt: Vision + OCR + Memory + Instructions
  ├─ 创建会话（若需要）: POST /api/chat/session/create
  ├─ 流式 LLM: ApiClient.completionStream() → POST /api/completion
  │   └─ 逐 chunk 更新 UI → _messages.add(assistant msg)
  ├─ 句子分块 → PipelineManager.addLLMResponse() → TTS pipeline
  └─ 保存会话: POST /api/chat/session/update
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

### 后端 API 路由表（LAV2 兼容）

| Endpoint | Method | 用途 | 已对接 |
|----------|--------|------|--------|
| /api/settings | GET | 获取设置 | ✅ |
| /api/settings/update | POST | 更新设置 | ✅ |
| /api/completion | POST | 流式 LLM 聊天 | ✅ |
| /api/tts | POST | TTS 合成 | ✅ |
| /api/tts/voices | GET | TTS 声音列表 | ✅ |
| /api/llm/models | GET | LLM 模型列表 | ✅ |
| /api/character/live2d/models | GET | Live2D 模型列表 | ✅ |
| /api/memory/context | POST | 记忆检索 | ✅ |
| /api/screenshot | GET | 截图+OCR | ✅ |
| /api/chat/session/* | CRUD | 会话管理 | ✅ |
| /api/rvc/* | Proxy | RVC 语音转换 | 待对接 |

---

## 关键文件索引

| 需要修改... | 去这里 |
|-------------|--------|
| 聊天消息逻辑 | lib/providers/chat_provider.dart |
| 后端 API 调用 | lib/services/api_client.dart |
| Pipeline 任务状态 | lib/services/pipeline_manager.dart |
| 会话存储 | lib/services/session_manager.dart |
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

### 添加新的设置页
1. `lib/screens/` 下新建 `xxx_screen.dart`
2. `lib/screens/home_screen.dart` 的 `_pages` map 中添加路由
3. `lib/widgets/app_sidebar.dart` 的 `_testPipeline`/`_footer` 添加新 key
4. 若需新 API → `lib/services/api_client.dart` 添加方法

### 添加新的消息类型
1. `lib/models/message.dart`: HistoryItem 扩展新字段
2. `lib/widgets/chat_bubble.dart`: 添加新气泡样式
3. `lib/providers/chat_provider.dart`: 处理新类型消息流

### 对接 WebSocket（未来）
1. `pubspec.yaml` 已包含 `web_socket_channel`
2. 在 `lib/services/` 新建 `ws_client.dart`
3. `lib/providers/chat_provider.dart` 替换 HTTP 流为 WS 事件流
4. Pipeline 状态通过 WS 实时推送

### 添加 TTS 音频播放
1. 使用 `audioplayers` 包（已在 pubspec.yaml）
2. `lib/services/` 新建 `audio_player.dart`
3. PipelineManager 的 `addTTSAudio` 后触发播放

### 添加 Live2D 渲染
1. 研究 `pixi-live2d-display` 的 Flutter 替代方案
2. 使用 Flutter WebView 嵌入 Live2D SDK 或直接使用 Cubism Native SDK
3. 在 `lib/screens/character_screen.dart` 替换占位容器

### 添加独立后端（Phase 2）
1. 创建 `backend/` 目录
2. 参考 `references/backend-architecture.md` 模板
3. 从 LocalAIVtuber2 移植核心服务模块
4. 添加 WebSocket 支持实时 Agent ↔ VTuber 通信

---

## 开发路线图

### Phase 1: 复现 LocalAIVtuber2 核心功能（当前阶段）
- [x] ✅ 项目结构搭建（Flutter Desktop）
- [x] ✅ 数据模型（Message, Task, Settings）
- [x] ✅ Provider 状态管理（ChatProvider, SettingsProvider）
- [x] ✅ ApiClient 后端 HTTP 对接（10+ API endpoints）
- [x] ✅ PipelineManager 流水线逻辑
- [x] ✅ SessionManager 会话管理
- [x] ✅ 侧边栏导航（10 页面）
- [x] ✅ 聊天界面（流式 LLM 响应）
- [x] ✅ LLM 设置页（System Prompt, API Relay）— 已修复 TextEditingController 生命周期
- [x] ✅ 角色设置页（Live2D/VRM 切换）— 已修复 settings 部分更新丢失字段
- [x] ✅ TTS 设置页（GPT-SoVITS, RVC）— 已修复 settings 部分更新丢失字段
- [x] ✅ 视觉设置页（截图 OCR）
- [x] ✅ 记忆页面（会话管理）
- [x] ✅ 直播设置页（YouTube 聊天）
- [x] ✅ Pipeline Monitor（实时流水线任务状态）
- [x] ✅ 通用设置页（服务器连接）
- [x] ✅ Windows 原生配置（CMake, runner）
- [x] ✅ Git 仓库初始化 + GitHub 推送
- [ ] ⬜ Flutter pub get + 编译验证
- [ ] ⬜ Live2D 角色渲染集成
- [ ] ⬜ TTS 音频播放集成
- [ ] ⬜ 端到端测试（连接 LAV2 后端）

### Phase 2: Agent × AI VTuber（subagent 多 Agent 协作）
- [ ] ⬜ 构建独立 FastAPI 后端（非依赖 LAV2）
- [ ] ⬜ WebSocket 实时双向通信
- [ ] ⬜ SubAgent 编排系统（multi-agent collaboration）
- [ ] ⬜ 上下文压缩（context compression）
- [ ] ⬜ 多 AI Provider（OpenAI, Anthropic, Google, Ollama）
- [ ] ⬜ Agent 任务委派（delegate_task）
- [ ] ⬜ 文件传输（带 SHA256 校验）
- [ ] ⬜ CronJob 定时任务调度

### Phase 3: 增强功能
- [ ] ⬜ CustomTkinter / 原生 Windows UI 备选方案
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

*此文档由 Hermes Agent 在 2026-05-09 根据 LocalAIVtuber2 架构生成。*
*每次阶段性完成后更新此文件并推送到 origin。*
