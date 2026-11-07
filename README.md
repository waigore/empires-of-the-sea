# Empires of the Sea

Naval strategy game built with **Godot 4**, targeting desktop (Windows, macOS, Linux) and mobile (Android, iOS).

## Requirements

- [Godot 4.x](https://godotengine.org/download) (standard build)
- Export templates for your target platforms
- Android: JDK 17+, Android SDK; iOS: macOS + Xcode

## Getting started

1. Open the project in Godot (`project.godot`).
2. Run the main scene (F5).
3. Export via **Project → Export** using the presets for desktop and mobile.

## Project layout

```
res://
├── scenes/       # Packed scenes (.tscn)
├── scripts/      # GDScript (.gd)
├── assets/       # Art, audio, fonts
├── ui/           # UI scenes and themes
└── autoload/     # Singletons
```

## Platforms

| Platform | Notes |
|----------|--------|
| Windows / Linux / macOS | Primary desktop targets |
| Android | Touch-first controls; test on device |
| iOS | Requires Apple developer setup for device builds |

Design for both mouse/keyboard and touch. Prefer resolution-independent UI (anchors, containers, theme scales).
