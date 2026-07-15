#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/dist/Codex Usage Bar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build -c release --package-path "$ROOT_DIR"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
/usr/bin/install -m 755 "$ROOT_DIR/.build/release/CodexUsageBar" "$MACOS_DIR/CodexUsageBar"
/usr/bin/install -m 644 "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/bin/install -m 644 "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
/usr/bin/install -m 644 "$ROOT_DIR/Resources/AppIcon.png" "$RESOURCES_DIR/AppIcon.png"
/usr/bin/install -m 644 "$ROOT_DIR/Resources/icon-codex-light.png" "$RESOURCES_DIR/icon-codex-light.png"
/usr/bin/install -m 644 "$ROOT_DIR/Resources/icon-codex-dark-color.png" "$RESOURCES_DIR/icon-codex-dark-color.png"

/usr/bin/codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
