# Chat Provider

**File:** `lib/providers/chat_provider.dart`

## Overview

Core state management for the chat system. Manages messages, sessions, LLM streaming, and pipeline integration.

## Key State

```dart
class ChatProvider extends ChangeNotifier {
  List<HistoryItem> _messages;        // Current session messages
  List<Session> _sessions;            // All sessions
  String? _activeSessionId;           // Current session
  bool _isStreaming;                  // LLM streaming active
  
  // Settings (synced from SettingsProvider)
  String? _llmBaseUrl;
  String? _llmApiKey;
  String? _llmModel;
}
```

## Key Methods

| Method | Description |
|--------|-------------|
| `sendMessage(text)` | Full send pipeline: memory → LLM → TTS |
| `createNewSession(title)` | Create named session |
| `renameSession(id, title)` | Inline rename |
| `deleteSession(id)` | Remove session + messages |
| `switchSession(id)` | Load different session |
| `initFromSavedState()` | Restore last session on startup |

## Streaming Flow

```
sendMessage()
  → add user message to _messages
  → notifyListeners()
  → backend.completionStream()
    → for each chunk: append to last assistant message
    → notifyListeners() (real-time UI update)
  → on done: save session to StorageService
```

## Related Files

- `lib/services/backend_service.dart` — Backend orchestration
- `lib/services/llm_service.dart` — API streaming
- `lib/services/session_manager.dart` — Session CRUD
- `lib/models/message.dart` — HistoryItem, Session models
