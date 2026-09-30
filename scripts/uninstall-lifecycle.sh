#!/bin/zsh
set -euo pipefail

USER_ID="$(/usr/bin/id -u)"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# 새 이름과 예전 이름(Codex Usage Bar)의 자동 실행 조건을 모두 제거한다.
for LABEL in local.mackim.CCusagebar.lifecycle local.mackim.CodexUsageBar.lifecycle; do
    /bin/launchctl bootout "gui/$USER_ID/$LABEL" 2>/dev/null || true
    /bin/rm -f "$LAUNCH_AGENTS_DIR/$LABEL.plist"
done

echo "CCusagebar 자동 실행 조건을 제거했습니다."
