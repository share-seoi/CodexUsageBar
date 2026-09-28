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

# 로컬 코드 서명 인증서가 있으면 그것으로 서명한다. 서명이 빌드마다 바뀌지 않아
# 키체인의 "항상 허용"이 다시 빌드해도 유지된다. 없으면 임시(ad-hoc) 서명을 쓴다.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-CodexUsageBar Local Code Signing}"
if /usr/bin/security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    /usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    echo "'$SIGN_IDENTITY' 인증서가 없어 임시 서명을 사용합니다 (다시 빌드하면 키체인 허용을 다시 묻습니다)." >&2
    /usr/bin/codesign --force --deep --sign - "$APP_DIR"
fi

echo "$APP_DIR"
