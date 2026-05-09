# AI VTuber Agent

A Flutter desktop application that reproduces and extends LocalAIVtuber2 — a fully local AI-powered virtual YouTuber.

## Features
- 10-page sidebar navigation (Chat, LLM, Character, Memory, Vision, TTS, Pipeline, Stream, Settings)
- Chat interface with streaming LLM responses (direct OpenAI-compatible API)
- Live2D character display (planned)
- TTS voice synthesis (edge-tts via subprocess)
- Screenshot vision + OCR
- Local memory search (keyword-based, no external DB)
- Session history management (JSON files)
- YouTube live chat integration (planned)

## Stack
- **Frontend:** Flutter Desktop (Windows)
- **Backend:** Self-contained Dart services (no external server needed)
- **State:** Provider (ChangeNotifier)
- **Storage:** `D:\AiVtuber_Agent_profile\` (Steam-style local saves)

## Quick Start

```bash
# Windows terminal:
cd D:\AiVtuber_Agent
flutter pub get
flutter run -d windows
```

## Architecture

The app is **fully self-contained** — no Python FastAPI backend required. All logic runs in-process:

- **LLM** — Direct HTTP/SSE calls to OpenAI-compatible APIs (SiliconFlow, OpenRouter, etc.)
- **TTS** — edge-tts CLI via subprocess, audio cached locally
- **Memory** — Keyword-matching across local session JSON files
- **Storage** — `D:\AiVtuber_Agent_profile\settings.json` + `sessions/*.json`

Configure your API relay in **LLM Settings** (base URL, API key, model).

## Profile Data

All user data stored at `D:\AiVtuber_Agent_profile\`:
```
D:\AiVtuber_Agent_profile\
├── settings.json          # LLM config, TTS voice, character settings
├── sessions\               # Chat session JSON files
│   ├── <uuid>.json
│   └── ...
├── tts_cache\              # Cached TTS audio files
└── screenshots\            # Captured screenshots
```

Like Steam game saves — keep, backup, or sync to cloud as you wish.

## Development

```bash
flutter pub get
flutter run -d windows
flutter build windows     # Release .exe
```
