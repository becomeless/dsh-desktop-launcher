#!/bin/bash
# 把 mac/ 下的素材组装成 "DeepSeek Harness.app"（一般由 install-macos.sh 调用）
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$DIR/build/DeepSeek Harness.app}"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$DIR/DSH-Launcher.sh" "$OUT/Contents/MacOS/launcher"
cp "$DIR/Info.plist" "$OUT/Contents/Info.plist"
cp "$DIR/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
chmod +x "$OUT/Contents/MacOS/launcher"
echo "built: $OUT"
