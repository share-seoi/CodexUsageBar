#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE_APP="$ROOT_DIR/dist/CCusagebar.app"
INSTALL_DIR="$HOME/Applications"
INSTALL_APP="$INSTALL_DIR/CCusagebar.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="local.mackim.CCusagebar.lifecycle.plist"
SOURCE_PLIST="$ROOT_DIR/Resources/$PLIST_NAME"
TARGET_PLIST="$LAUNCH_AGENTS_DIR/$PLIST_NAME"
CODEX_SUPPORT_DIR="$HOME/Library/Application Support/Codex"
CLAUDE_SUPPORT_DIR="$HOME/Library/Application Support/Claude"
USER_ID="$(/usr/bin/id -u)"
SERVICE_TARGET="gui/$USER_ID/local.mackim.CCusagebar.lifecycle"

# 예전 이름(Codex Usage Bar)으로 설치돼 있으면 자동 실행 조건과 앱을 걷어낸다.
# 저장된 설정·마지막 사용량은 새 앱이 처음 켜질 때 옮겨 온다.
LEGACY_SERVICE_TARGET="gui/$USER_ID/local.mackim.CodexUsageBar.lifecycle"
LEGACY_PLIST="$LAUNCH_AGENTS_DIR/local.mackim.CodexUsageBar.lifecycle.plist"
LEGACY_APP="$INSTALL_DIR/Codex Usage Bar.app"
/bin/launchctl bootout "$LEGACY_SERVICE_TARGET" 2>/dev/null || true
/bin/rm -f "$LEGACY_PLIST"
/usr/bin/pkill -x CodexUsageBar 2>/dev/null || true
/bin/rm -rf "$LEGACY_APP"

mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENTS_DIR"
/usr/bin/pkill -x CCusagebar 2>/dev/null || true
/usr/bin/ditto "$SOURCE_APP" "$INSTALL_APP"
/usr/bin/install -m 644 "$SOURCE_PLIST" "$TARGET_PLIST"
/usr/libexec/PlistBuddy \
    -c "Set :ProgramArguments:0 $INSTALL_APP/Contents/MacOS/CCusagebar" \
    "$TARGET_PLIST"
/usr/libexec/PlistBuddy \
    -c "Set :WatchPaths:0 $CODEX_SUPPORT_DIR/SingletonLock" \
    "$TARGET_PLIST"
/usr/libexec/PlistBuddy \
    -c "Set :WatchPaths:1 $CODEX_SUPPORT_DIR" \
    "$TARGET_PLIST"
/usr/libexec/PlistBuddy \
    -c "Set :WatchPaths:2 $CLAUDE_SUPPORT_DIR" \
    "$TARGET_PLIST"

/bin/launchctl bootout "$SERVICE_TARGET" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$USER_ID" "$TARGET_PLIST"
/bin/launchctl enable "$SERVICE_TARGET"
/bin/launchctl kickstart -k "$SERVICE_TARGET"

echo "$INSTALL_APP"
echo "$TARGET_PLIST"
