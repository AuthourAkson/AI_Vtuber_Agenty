# Architecture Overview

## Tech Stack

- **Frontend:** Flutter Desktop (Windows .exe) + Provider state management
- **Window:** bitsdojo_window (frameless) + flutter_acrylic (Mica blur)
- **UI:** ShadTheme (shadcn/ui style, Material3 base) + 16 ThemePresets
- **i18n:** AppLocalizations (en / zh-CN / zh-TW), 220+ strings
- **Backend:** Self-contained Dart service layer (BackendService)
- **LLM:** OpenAI-compatible API (SiliconFlow, OpenRouter, Anthropic, Google, Ollama)
- **TTS:** edge-tts CLI subprocess + local audio cache
- **Storage:** D:\AiVtuber_Agent_profile\ (Steam-style local archive)

## Directory Layout

```
AiVtuber_Agent/
├── lib/
│   ├── main.dart              — Entry point
│   ├── app.dart               — MaterialApp, ShadTheme, i18n
│   ├── models/                — Data models
│   ├── providers/             — ChangeNotifier state management
│   ├── services/              — Backend business logic
│   ├── screens/               — UI pages (sidebar navigation)
│   ├── widgets/               — Reusable components
│   └── l10n/                  — i18n localization
├── assets/                    — Static resources (Live2D, VRM)
├── windows/                   — Windows native code
└── project-summary/           — This documentation
```

## Key Design Decisions

1. **Monolithic Dart backend** — no external Python dependency for core logic
2. **Provider over BLoC/Riverpod** — simpler, sufficient for desktop app
3. **Sidebar navigation** — collapsible, matches shadcn/ui patterns
4. **Local-first storage** — all data in D:\AiVtuber_Agent_profile\
