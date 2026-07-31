# Data Flow

## Message Send Flow

```
User Input (ChatInput)
  → ChatProvider.sendMessage()
    → MemoryService keyword match
    → LLMService SSE stream (OpenAI-compatible API)
    → PipelineManager: LLM → TTS → Audio
    → StorageService save session
```

## Session Management Flow

```
Create: "+" button → dialog → createNewSession(title) → StorageService
Rename: long-press / edit icon → inline TextField → renameSession(id, title)
Display: activeSessionTitle → stored title, fallback to first user message
```

## Pipeline Flow

```
Task: created
  → LLM streaming (llm_started → llm_finished)
  → Per-sentence TTS (PipelineManager.addTTSAudio)
  → Task: tts_finished
  → Audio playback
  → Task: task_finished
```

## Provider Dependency Graph

```
MaterialApp
├── AppearanceProvider (theme, language, font)
├── SettingsProvider (API config, TTS settings)
├── ChatProvider (messages, sessions, LLM streaming)
├── AgentManager (WenzAgent multi-agent LAN)
└── LiveStreamProvider (Bilibili live, danmaku)
```
