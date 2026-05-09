# AI VTuber Agent

A Flutter desktop application that reproduces and extends LocalAIVtuber2 — a fully local AI-powered virtual YouTuber.

## Features (Current - Replicating LAV2)
- 10-page sidebar navigation (Home/LLM, Character, Memory, Input, Vision, TTS, Pipeline Monitor, Stream, Settings)
- Chat interface with streaming LLM responses
- Live2D character display (planned)
- TTS voice synthesis via backend API
- Screenshot vision + OCR
- Vector memory with Qdrant
- Session history management
- YouTube live chat integration

## Stack
- **Frontend:** Flutter Desktop (Windows)
- **Backend:** Connects to LocalAIVtuber2 FastAPI (localhost:8000)
- **State:** Provider (ChangeNotifier)

## Quick Start

```bash
# Install Flutter SDK on Windows
# Then:
flutter pub get
flutter run -d windows
```

## Backend Dependency

This app requires the LocalAIVtuber2 backend running on `localhost:8000`.
See `D:\LocalAIVtuber2\readme.md` for backend setup.

## Development

```bash
flutter pub get
flutter run -d windows
```
