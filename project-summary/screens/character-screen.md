# Character Screen

**File:** `lib/screens/character_screen.dart`

## Overview

Manages the virtual character display — Live2D or VRM 3D model, chroma key, desktop pet, and eye tracking.

## Key Features

- **Live2D / VRM toggle** — switch between 2D and 3D character rendering
- **Model management** — upload, select, delete Live2D/VRM model files
- **Chroma Key** — pure green background for OBS keying (color picker)
- **Desktop Pet** — PyQt6 floating transparent window with eye tracking
- **Eye tracking** — webcam-based gaze following

## Technical Details

- Live2D: PixiJS WebView + Cubism SDK
- VRM: Three.js WebView + @pixiv/three-vrm
- Chroma key color persisted via SharedPreferences
- Desktop pet: separate PyQt6 subprocess

## Related Files

- `lib/widgets/live2d_view.dart` — Live2D WebView wrapper
- `lib/widgets/vrm_view.dart` — VRM WebView wrapper
- `lib/services/live2d_server.dart` — HTTP file server for model assets
- `lib/services/live2d_model_service.dart` — Model file management
- `lib/services/vrm_model_service.dart` — VRM model management
- `assets/live2d/renderer.html` — PixiJS rendering page
- `assets/vrm/vrm_renderer.html` — Three.js rendering page
