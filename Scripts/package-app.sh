#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"

echo "▶️ Building DockJumper ($CONFIGURATION)…"
BIN_PATH=$(swift build --configuration "$CONFIGURATION" --show-bin-path)
PRODUCT="$BIN_PATH/DockJumper"
RESOURCE_BUNDLE="$BIN_PATH/DockJumper_DockJumper.bundle"

if [[ ! -f "$PRODUCT" ]]; then
  echo "❌ Executable not found at $PRODUCT" >&2
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "❌ Resource bundle not found at $RESOURCE_BUNDLE" >&2
  exit 1
fi

APP_ROOT="Dist/DockJumper.app"
CONTENTS="$APP_ROOT/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "🧹 Cleaning $APP_ROOT"
rm -rf "$APP_ROOT"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "📦 Copying executable and resources"
cp "$PRODUCT" "$MACOS_DIR/DockJumper"
chmod +x "$MACOS_DIR/DockJumper"
cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"

if [[ ! -f AppBundle/AppIcon.icns ]]; then
  echo "❌ AppBundle/AppIcon.icns not found. Please run Scripts/make-icon.sh first." >&2
  exit 1
fi
cp AppBundle/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"

echo "📝 Installing Info.plist"
cp AppBundle/Info.plist "$CONTENTS/Info.plist"

echo "✅ DockJumper.app written to $APP_ROOT"
