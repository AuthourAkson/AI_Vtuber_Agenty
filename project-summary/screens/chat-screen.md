# Chat Screen

**File:** `lib/screens/chat_screen.dart`

## Overview

The main chat interface. Displays conversation messages, session management, and quick settings.

## Key Components

- **Message list** — `ListView.builder` with `ChatBubble` widgets
- **Session side panel** — slide-in panel showing all sessions with inline rename
- **Settings panel** — system prompt, temperature, API relay selection
- **Input area** — `ChatInput` widget with send button

## User Interactions

1. Type message → click Send → LLM streaming response
2. "+" button → create new named session
3. Session list → switch between conversations
4. Long-press session → inline rename
5. Gear icon → system prompt & model settings

## Related Files

- `lib/widgets/chat_bubble.dart` — Message bubble rendering (Markdown + LaTeX)
- `lib/widgets/chat_input.dart` — Text input + send button
- `lib/widgets/side_panel.dart` — Sliding panel animation
- `lib/providers/chat_provider.dart` — State management
- `lib/services/llm_service.dart` — API calls
