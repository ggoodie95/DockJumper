# DockJumper

DockJumper is a tiny native macOS game built with Swift Package Manager, AppKit, and SpriteKit. The app creates a floating 480×320 window that hosts a SpriteKit scene running at 60 FPS. Use the keyboard to move the player left and right or to jump across short platforms.

## Controls
- `←` / `A`: move left
- `→` / `D`: move right
- `Space`: jump
- `⌘Q` or close window: quit the game

## Build & Run
1. Clean any previous build artifacts with `swift clean`.
2. Compile the executable with `swift build -v`.
3. Launch from Terminal using `swift run DockJumper -v`.

When launched, the scene requests keyboard focus automatically. If running from Xcode, be sure the “DockJumper” scheme targets “My Mac”.

## Project Layout
```
DockJumper/
├── Package.swift
├── Sources/
│   └── DockJumper/
│       ├── GameScene.swift
│       └── main.swift
├── .gitignore
└── README.md
```
