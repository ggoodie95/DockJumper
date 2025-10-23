#!/usr/bin/env bash
set -euo pipefail

SRC_IMAGE="${1:-AppBundle/AppIcon.png}"
ICONSET_DIR="AppBundle/AppIcon.iconset"
OUT_ICNS="AppBundle/AppIcon.icns"

if [[ ! -f "$SRC_IMAGE" ]]; then
  echo "❌ Source image not found at $SRC_IMAGE" >&2
  echo "   Place the dock artwork there (PNG, ideally 1024×1024) and rerun." >&2
  exit 1
fi

echo "🎨 Generating iconset from $SRC_IMAGE"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sizes=(16 32 64 128 256 512)
for size in "${sizes[@]}"; do
  double=$((size * 2))
  sips -z "$size" "$size" "$SRC_IMAGE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  sips -z "$double" "$double" "$SRC_IMAGE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

echo "🧰 Converting iconset to icns"
iconutil -c icns "$ICONSET_DIR" -o "$OUT_ICNS"

echo "🧹 Cleaning temporary iconset"
rm -rf "$ICONSET_DIR"

echo "✅ Icon written to $OUT_ICNS"
