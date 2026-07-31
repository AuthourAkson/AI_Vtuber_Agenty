# LLM Service

**File:** `lib/services/llm_service.dart`

## Overview

Direct API client for OpenAI-compatible LLM providers. Supports SSE streaming, multiple providers, and system prompt management.

## Supported Providers

- **SiliconFlow** — default, DeepSeek models
- **OpenRouter** — multi-model gateway
- **Anthropic** — Claude models
- **Google** — Gemini models
- **Ollama** — local models

## Key Methods

```dart
// Stream completion with SSE
Stream<String> completionStream({
  required List<Map<String, String>> messages,
  String? systemPrompt,
  double temperature = 0.7,
});

// Single-shot completion
Future<String> completion({...});
```

## Configuration

- baseUrl, apiKey, model stored in `settings.json`
- System prompt editable in LLM settings screen
- Temperature, maxTokens configurable per provider

## Related Files

- `lib/screens/llm_screen.dart` — Settings UI
- `lib/providers/settings_provider.dart` — Config state
- `lib/models/settings.dart` — AppSettings model
