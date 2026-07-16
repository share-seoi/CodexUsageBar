# Codex Usage Bar

macOS 메뉴 막대에서 Codex의 남은 사용량을 퍼센트로 보여주는 작은 AppKit 앱입니다.

## 동작 방식

- Codex가 로컬 세션에 이미 기록한 최신 rate-limit 스냅샷을 사용합니다.
- 로그인 토큰이나 `~/.codex/auth.json`을 직접 읽지 않습니다.
- 평소에는 20초마다 최근 세션 파일의 끝부분만 짧게 확인하며 별도 프로세스나 네트워크 요청을 만들지 않습니다.
- 앱 시작과 **지금 새로고침**에서는 Codex App Server로 계정 rate-limit을 1회 조회하고 즉시 프로세스를 종료합니다.
- 메뉴 막대의 퍼센트는 현재 한도들 중 **가장 적게 남은 값**입니다.
- 메뉴를 열면 5시간/주간 한도와 초기화 시각을 각각 확인할 수 있습니다.
- Dock 아이콘이나 일반 창을 만들지 않습니다.
- Codex 앱(`com.openai.codex`)이 실행될 때만 메뉴 막대 앱이 켜지고, Codex 앱이 종료되면 함께 종료됩니다.
- Codex가 꺼져 있을 때는 `launchd`의 파일 변경 조건만 등록되어 있으며 감시 프로세스는 상주하지 않습니다.

Codex를 이 Mac에서 사용하면 각 응답 뒤에 값이 갱신되어 최대 20초 안에 메뉴 막대에 반영됩니다.
다른 기기나 Codex 화면과 값이 다를 때는 **지금 새로고침**을 누르면 실시간 계정 값을 다시 읽습니다.

## 빌드

Codex 또는 ChatGPT macOS 앱이 `/Applications`에 설치된 상태에서:

```bash
./scripts/build-app.sh
./scripts/install-lifecycle.sh
```

생성 위치: `dist/Codex Usage Bar.app`

설치 위치: `~/Applications/Codex Usage Bar.app`

설치 스크립트는 `~/Library/LaunchAgents/local.mackim.CodexUsageBar.lifecycle.plist`를 등록합니다. 로그인할 때 한 번 상태를 확인하고, 이후 Codex의 `SingletonLock` 생성/삭제를 시작 조건으로 사용합니다.

자동 실행 조건만 제거하려면:

```bash
./scripts/uninstall-lifecycle.sh
```

## 진단

메뉴 UI 없이 현재 값을 한 번 확인할 수 있습니다.

```bash
.build/release/CodexUsageBar --print-usage
.build/release/CodexUsageBar --print-live-usage
```
