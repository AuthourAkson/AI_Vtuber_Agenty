# Settings Model

**File:** `lib/models/settings.dart`

## Overview

Central configuration model. Serialized to/from `D:\AiVtuber_Agent_profile\settings.json`.

## Key Fields

```dart
class AppSettings {
  // LLM Config
  String baseUrl;        // API endpoint
  String apiKey;         // Auth token
  String model;          // Model name
  String systemPrompt;   // Default system prompt
  double temperature;    // 0.0 - 2.0

  // TTS Config
  String ttsEngine;      // 'edge-tts' | 'gpt-sovits'
  String ttsVoice;       // Voice name
  double ttsSpeed;       // Playback speed
  
  // Character Config
  String characterMode;  // 'live2d' | 'vrm'
  String chromaKeyColor; // Hex color for keying
  
  // GPT-SoVITS
  String gptSovitsPythonPath;
  
  // Vision
  bool visionEnabled;
  int screenshotInterval;
}
```

## Persistence

- `StorageService.loadSettings()` → JSON decode → `AppSettings.fromJson()`
- `StorageService.saveSettings()` → `AppSettings.toJson()` → JSON encode
- Auto-save on every change via `SettingsProvider`

## Related Files

- `lib/services/storage_service.dart` — JSON read/write
- `lib/providers/settings_provider.dart` — State + auto-save
