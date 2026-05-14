# AI VTuber Agent

A Flutter desktop application that reproduces and extends LocalAIVtuber2 — a fully local AI-powered virtual YouTuber. Frontend visuals are a 1:1 replica of LAV2's React + shadcn/ui design.

## Features

- **10-page sidebar navigation** with collapsible shadcn-style sidebar (200px/48px)
- **Chat interface** with streaming LLM responses (direct OpenAI-compatible API)
- **Markdown rendering** — bold, italic, lists, links, blockquotes
- **Code blocks** with dark-themed styling + native text selection for copy
- **LaTeX math** — inline `$...$` and display `$$...$$` via flutter_math_fork
- **Chemical formulas** — `\ce{H2O}` auto-converted to subscripts/superscripts
- **Session management** — slide-in panel with create/load/delete sessions
- **LLM Monitor** — real-time system/vision/ocr/memory context display
- **Live2D character** display with WebView + PixiJS rendering
- **TTS voice synthesis** (edge-tts via subprocess)
- **Screenshot vision + OCR**
- **Local memory search** (keyword-based, no external DB)
- **Pipeline Monitor** — real-time LLM→TTS→Audio task tracking
- **Settings side panel** — API config, system prompt, monitor toggle

## Visual Design

The UI is a faithful replica of LocalAIVtuber2's **shadcn/ui dark theme**:

| Element | Color |
|---------|-------|
| Background | `#1A1A1A` |
| Cards | `#252525` |
| Secondary | `#2E2E2E` |
| Borders | `rgba(255,255,255,0.1)` |
| Text | `#F5F5F5` / `#9E9E9E` |
| Corner radius | 6px (md), 8px (lg), 10px (input) |

## Stack

- **Frontend:** Flutter Desktop (Windows) — Material 3
- **Window:** bitsdojo_window (frameless) + flutter_acrylic (Mica blur)
- **State:** Provider (ChangeNotifier)
- **Markdown:** flutter_markdown + flutter_math_fork (LaTeX)
- **Backend:** Self-contained Dart services (no external server needed)
- **Storage:** `D:\AiVtuber_Agent_profile\` (Steam-style local saves)

## Quick Start

```bash
# Windows terminal:
cd D:\AiVtuber_Agent
flutter pub get
flutter run -d windows
```

## Architecture

The app is **fully self-contained** — no Python FastAPI backend required:

- **LLM** — Direct HTTP/SSE to OpenAI-compatible APIs
- **TTS** — edge-tts CLI subprocess, audio cached locally
- **Memory** — Keyword-matching across local session JSON files
- **Storage** — `D:\AiVtuber_Agent_profile\settings.json` + `sessions/*.json`

Configure API relay in the **Settings side panel** (⚙) on the Chat page.

## Profile Data

```
D:\AiVtuber_Agent_profile\
├── settings.json          # LLM config, TTS voice, character settings
├── sessions\               # Chat session JSON files
├── tts_cache\              # Cached TTS audio files
└── screenshots\            # Captured screenshots
```

## Development

```bash
flutter pub get
flutter run -d windows
flutter build windows     # Release .exe
```
