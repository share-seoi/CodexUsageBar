#!/bin/zsh
set -euo pipefail

PLIST_NAME="local.mackim.CodexUsageBar.lifecycle.plist"
TARGET_PLIST="$HOME/Library/LaunchAgents/$PLIST_NAME"
USER_ID="$(/usr/bin/id -u)"
SERVICE_TARGET="gui/$USER_ID/local.mackim.CodexUsageBar.lifecycle"

/bin/launchctl bootout "$SERVICE_TARGET" 2>/dev/null || true
/bin/rm -f "$TARGET_PLIST"

echo "Codex Usage Bar 자동 실행 조건을 제거했습니다."
