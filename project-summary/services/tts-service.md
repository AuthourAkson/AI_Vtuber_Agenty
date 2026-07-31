# TTS Service

**File:** `lib/services/tts_service.dart`

## Overview

Text-to-Speech synthesis using edge-tts CLI as a subprocess. Caches generated audio locally.

## Engine Support

- **edge-tts** — Microsoft Edge TTS (default, free)
- **GPT-SoVITS** — Custom voice cloning (external Python)

## Key Methods

```dart
// Synthesize text to audio file
Future<String?> synthesize(String text, {String? voice});

// Get cached audio path
String getCachePath(String textHash);
```

## Caching

- Audio files cached in `D:\AiVtuber_Agent_profile\tts_cache\`
- Cache key: SHA256 hash of text + voice
- Auto-cleanup on cache overflow

## GPT-SoVITS Integration

- External Python: `D:\GPT-SoVITS-v2pro-20250604\`
- Uses bundled `runtime\python.exe` (Py3.9 + CUDA)
- v4 model with LoRA support
- Subprocess managed with Job Object for auto-kill

## Related Files

- `lib/screens/tts_screen.dart` — Settings UI
- `lib/models/settings.dart` — Voice config
