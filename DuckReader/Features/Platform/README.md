# Platform Features

Mac Catalyst and iPad-exclusive features. All degrade gracefully on iPhone.

## Modules
- **DuckShortcuts** — Complete keyboard shortcut catalog
- **MultiWindowManager** — Multi-window reading sessions
- **TrackpadGestures** — Pointer/cursor integration
- **StageManagerLayout** — Adaptive layout for Stage Manager
- **PlatformCapabilities** — Runtime platform feature detection
- **ReadingTouchBar** — Mac Touch Bar controls

## Design
- All features wrapped in `#if os() / #if targetEnvironment()` guards
- iPhone gracefully degrades (no-op or single-window fallback)
- Keyboard shortcuts use standard Apple HIG conventions
