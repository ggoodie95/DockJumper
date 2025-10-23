# DockJumper

DockJumper is a tiny native macOS game built with Swift Package Manager, AppKit, and SpriteKit. The app opens a compact 520×360 floating window that hosts a 60 FPS SpriteKit scene. Use the keyboard to scale ever-tougher platforms, rack up points, and chase the leaderboard.

> **Pre-release:** this build is a work-in-progress headed for a Mac App Store launch once gameplay, polish, and monetisation features are complete.

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

## Support The Project
- ☕ Keep the “Support the Reaper” button in game or visit **[Buy Me a Coffee](https://buymeacoffee.com/ggoodie95)** to help fund future updates.
- Optional rewarded ads are planned for the 1.0 release so that players can contribute without spending money.

### Create a macOS `.app` bundle
1. Drop your dock icon PNG into `AppBundle/AppIcon.png` (1024×1024 recommended).  
   Run the helper to produce `AppBundle/AppIcon.icns`:
   ```bash
   ./Scripts/make-icon.sh
   ```
2. Package the game into `Dist/DockJumper.app` (Release by default):
   ```bash
   ./Scripts/package-app.sh [debug|release]
   ```
3. Open `Dist/DockJumper.app` or move it into `/Applications` / your Dock.
4. Re-run both scripts whenever you change the artwork or code.

## Project Layout
```
DockJumper/
├── Package.swift
├── AppBundle/
│   ├── AppIcon.icns
│   ├── AppIcon.png      # source image you provide
│   └── Info.plist
├── Scripts/
│   ├── make-icon.sh
│   └── package-app.sh
├── Sources/
│   └── DockJumper/
│       ├── GameScene.swift
│       └── main.swift
├── .gitignore
└── README.md
```
