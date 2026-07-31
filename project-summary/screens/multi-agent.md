# Multi-Agent System

**File:** `lib/screens/multi_agent_screen.dart`

## Overview

WenzAgent-based multi-agent collaboration system. Manages employee agents, LAN communication, skill library, and agent chat.

## Key Components

- **Secondary sidebar** — Chat / Contacts / Skills / Settings modes
- **Employee management** — create, edit, delete AI employees
- **Agent chat** — real-time conversation with selected employee
- **Global skill library** — MCP / Folder / Config skill types
- **Settings panels** — General, Appearance, AI, LAN, Logs, Sync, Devices, MCP, Permissions

## Architecture

```
AgentManager (ChangeNotifier)
  → WenzAgentService (SDK wrapper)
    → WenzAgent SDK (D:/wenzagent-1.0.4/)
      → LAN discovery + P2P messaging
      → Skill management (GlobalSkillManager, SkillStore)
      → Agent sessions with tool calling
```

## Employee Status Display

Each employee shows:
- Online/offline status indicator
- Current task / activity
- Message notification badge
- Last active timestamp

## Related Files

- `lib/providers/multi_agent_provider.dart` — AgentManager state
- `lib/services/wenzagent_service.dart` — SDK API wrapper
- `lib/screens/multi_agent_appearance.dart` — Appearance settings
- `pubspec.yaml` — wenzagent path dependency
