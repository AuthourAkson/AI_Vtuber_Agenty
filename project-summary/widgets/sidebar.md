# App Sidebar

**File:** `lib/widgets/app_sidebar.dart`

## Overview

Collapsible left navigation sidebar with shadcn/ui styling.

## Features

- **Expand/collapse** — 200px expanded, 48px collapsed with tooltips
- **Two sections** — Test Pipeline (top) + Footer (bottom)
- **Active state** — highlighted with accent color
- **Smooth animation** — AnimatedContainer 200ms ease

## Navigation Items

### Test Pipeline
- Home (Chat)
- Character
- Memory
- Agents (Multi-Agent)

### Footer
- Input (Voice)
- Vision (OCR)
- TTS
- Pipeline
- Stream (Bilibili)
- Settings

## Styling

```dart
// Colors from ShadTheme
sidebar          — background
sidebarBorder    — right border
sidebarAccent    — active item background
sidebarAccentForeground — active item text/icon
mutedForeground  — inactive item text/icon
```

## Related Files

- `lib/screens/home_screen.dart` — Page routing
- `lib/l10n/app_localizations.dart` — i18n labels
