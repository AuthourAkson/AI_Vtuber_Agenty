# 🤖 AI VTuber Agent

[English](README.md) · [简体中文](README.zh-CN.md)

> **集 Live2D / VRM 角色、Bilibili 直播、多 TTS 语音、WenzAgent 多智能体协作于一体的 Flutter Desktop AI VTuber 应用。**
>
> 界面采用 shadcn/ui 风格，支持 16 套主题、中/英/繁国际化，并扩展了员工人格化、弹幕派活、confirm 交互和 A/I/U/E/O 口型同步。

---

## ✨ 亮点

- 🎭 **Live2D + VRM 双渲染引擎**：WebView + PixiJS / Three.js，支持 OBS 弹窗与色度键抠像
- 🗣 **多 TTS 引擎**：Edge-TTS、GPT-SoVITS，统一生成音量 + A/I/U/E/O 口型时间线
- 👥 **WenzAgent 多智能体网络**：员工管理、人格化形象/音色/系统提示词、Skill 技能系统、MCP Server
- 📺 **Bilibili 直播**：弹幕自动回复、Setlist、观众 `@员工` 直接派活
- 🧠 **AgentMark / MarkdownText IDE**：文件树 + Markdown 编辑器 + AI 任务中心，支持员工和 Claude Code CLI 执行器
- ☁️ **WebDAV / 本地增量同步**：内容哈希去重，避免重复上传
- 🌗 **16 套 shadcn 主题** + i18n（英文 / 简体中文 / 繁体中文）

---

## 🖼 页面截图

| 页面 | 预览 |
|------|------|
| 首页 / 聊天 | ![Home](image/HomePage.png) |
| 角色 | ![Character](image/CharacterPage.png) |
| TTS | ![TTS](image/TTsPage.png) |
| 记忆 | ![Memory](image/MemoryPage.png) |
| 直播 | ![Stream](image/StreamPage.png) |
| 流水线 | ![Pipeline](image/StreamPipelinePage.png) |
| 多智能体会话 | ![Agent Chat](image/MultiAgent-EmployeeSession.png) |
| 多智能体设置 | ![Agent Settings](image/MultiAgent-Settings.png) |
| 数据同步 | ![Data Sync](image/MultiAgent-Settings-DataSync.png) |
| MarkdownText 1 | ![MarkdownText 1](image/MarkdownTextPage1.png) |
| MarkdownText 2 | ![MarkdownText 2](image/MarkdownTextPage2.png) |
| MarkdownText 3 | ![MarkdownText 3](image/MarkdownTextPage3.png) |
| MarkdownText 4 | ![MarkdownText 4](image/MarkdownTextPage4.png) |

---

## 🚀 功能特性

### 🧠 AI 聊天与角色

- 流式 LLM 聊天，兼容 OpenAI / SiliconFlow / OpenRouter / Anthropic / Google / Ollama
- Live2D 与 VRM 3D 角色渲染
- 会话管理、Markdown / LaTeX / 化学公式渲染
- 截图视觉识别 + OCR
- 本地记忆搜索

### 🎙 TTS 语音与口型同步

- **Edge-TTS** 与 **GPT-SoVITS** 双引擎
- 统一生成音频 + 音量序列 + **A/I/U/E/O 口型时间线**
- VRM 支持 `aa / ih / ou / ee / oh` 五表情口型
- Live2D 支持音量驱动张嘴
- 支持 OBS Pop-Out 弹窗实时口型同步
- 内置 100ms 口型提前量，降低 WebView 弹窗延迟

### 📺 Bilibili 直播与弹幕派活

- Bilibili 弹幕 HTTP 轮询、自动回复
- 滑动窗口 / 顺序两种弹幕回复模式
- Setlist 编辑器：系统提示 / AI 回复 / 聊天 / 唱歌节点
- 观众可直接向 WenzAgent 员工派活：
  - `@员工名 任务内容`
  - `@agent 任务内容`
  - `!agent 任务内容`
- Agent 的 confirm 确认请求通过 TTS 播报，观众可用弹幕 `1 / 2 / 方案名` 选择


### 🤝 WenzAgent 多智能体

- LAN 设备发现、员工创建/删除/会话管理
- **员工人格化**：为每个员工绑定 Live2D / VRM 形象、语音、系统提示词
- **confirm 工具**：会话中渲染为可点击选项卡片
- **权限管理**：细粒度工具权限审批
- **数据同步**：WebDAV / 本地文件夹增量同步

#### 🛠 Skill 技能系统

Multi-Agent 内置完整 Skill 体系，可为不同员工装配不同能力：

| 类型 | 说明 | 使用方式 |
|------|------|----------|
| **Global Skill** | 全局技能库，可复用给任意员工 | Skills 面板添加 → 选择 Folder / MCP |
| **Folder Skill** | 将本地包含 `SKILL.md` 的文件夹复制为技能 | 选择文件夹 → 自动拷贝到 `wenzagent/skills/folder` |
| **MCP Skill** | 通过 MCP Server 接入外部工具服务 | MCP 配置面板添加 `mcpServers` |

- 支持技能启用/停用、员工技能绑定、技能删除
- 员工打开时会自动同步全局技能与员工技能

#### 🔌 MCP Server 支持

Multi-Agent Settings 提供完整的 **MCP 配置面板**：

- 可视化添加 MCP Server（JSON 格式 `mcpServers`）
- 支持本地命令型 MCP（如 `npx`）与远程 HTTP MCP
- 可将 MCP 技能添加到指定员工，让 Agent 调用外部工具
- 配置存储在 WenzAgent 数据目录，随同步一起备份

### 📝 MarkdownText IDE（AgentMark）

- 五段式项目 IDE：顶栏 + 文件树 + Markdown 编辑区 + AI 任务中心 + 状态栏
- 支持员工 / Claude Code CLI 执行器
- 流式任务事件、工具调用进度、会话日志
- 任务卡片：查看 / 编辑 / 重试 / 删除
- 服务商选择器与持久化

### 🧰 其他

- Pipeline Monitor：LLM → TTS → Audio 实时任务跟踪
- 16 套 shadcn 风格主题，一键切换
- i18n：English / 简体中文 / 繁體中文
- 自动更新检查、About 面板、官网跳转

---

## 🏗 技术栈

| 层 | 技术 |
|----|------|
| 前端 | Flutter Desktop (Windows) |
| 状态 | Provider (ChangeNotifier) |
| UI | ShadTheme / shadcn-ui 风格，Material 3 |
| 窗口 | bitsdojo_window + flutter_acrylic |
| Live2D | PixiJS + Live2D Cubism SDK |
| VRM | Three.js + @pixiv/three-vrm |
| TTS | edge-tts CLI / GPT-SoVITS HTTP API + ffmpeg |
| 多智能体 | WenzAgent Dart SDK (LAN) |
| 数据库 | sqlite3（Windows 系统 winsqlite3） |
| 存储 | `D:\AiVtuber_Agent_profile\` 本地 JSON / SQLite |

---

## 🚦 快速开始

```bash
cd D:\AiVtuber_Agent
flutter pub get
flutter run -d windows
```

---

## 📂 数据目录

```
D:\AiVtuber_Agent_profile\
├── settings.json              # LLM / TTS / 角色设置
├── sessions\                   # 聊天会话 JSON
├── tts_cache\                  # TTS 音频缓存
├── screenshots\                # 截图
├── models\live2d\              # Live2D 模型
├── models\vrm\                 # VRM 模型
├── wenzagent\
│   ├── db\                     # WenzAgent SQLite 数据
│   └── skills\
│       ├── folder\             # Folder Skill
│       └── mcp\                # MCP Skill
└── wenzagent_profiles.json     # 多智能体配置 + 员工人格化
```

## 🛠 开发

```bash
flutter pub get
flutter run -d windows
flutter build windows --release
```