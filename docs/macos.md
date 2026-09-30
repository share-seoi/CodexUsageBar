# CCusagebar (mac) 상세 안내

[← README로 돌아가기](../README.md)


아래는 macOS AppKit 버전의 동작 및 설치 안내입니다.

- 앱 이름은 `CCusagebar`, 번들 ID는 `local.mackim.CCusagebar`입니다. 번들 ID가 바뀌었기 때문에 키체인 접근을 한 번 더 물을 수 있습니다.

- 지금 앞에 있는 앱이 Codex면 Codex 사용량, Claude면 Claude 사용량을 표시합니다.
- 다른 앱으로 전환하면 마지막으로 사용한 쪽(Codex 또는 Claude)을 계속 표시합니다.
- 메뉴를 열면 두 앱의 한도를 모두 볼 수 있고, 현재 메뉴 막대에 표시 중인 쪽 카드가 강조됩니다.
- 메뉴의 **Codex·Claude 둘 다 표시**(⌘B)를 켜면 두 앱이 메뉴 막대 항목 하나 안에 각자 아이콘과 함께 나란히 표시됩니다(Codex 왼쪽, Claude 오른쪽). 항목을 새로 만들지 않아 메뉴 막대가 꽉 차도 노치 뒤로 숨지 않습니다. 두 앱 모두 값을 받은 뒤부터 나란히 나오고, 이때 Claude는 1분마다 조회합니다. 설정은 저장됩니다.

## 동작 방식 (Codex)

- Codex가 로컬 세션에 이미 기록한 최신 rate-limit 스냅샷을 사용합니다.
- 로그인 토큰이나 `~/.codex/auth.json`을 직접 읽지 않습니다.
- 평소에는 20초마다 최근 세션 파일의 끝부분만 짧게 확인하며 별도 프로세스나 네트워크 요청을 만들지 않습니다.
- 앱 시작, **지금 새로고침**, Codex로 전환할 때(마지막 조회 후 1분이 지났을 때만)는 Codex App Server로 계정 rate-limit을 1회 조회하고 즉시 프로세스를 종료합니다.
- 한도마다 `5h`(5시간)·`W`(주간) 이름표를 붙여 표시합니다. 주간 한도만 있으면 `W 88%`, 둘 다 있으면(Claude, Codex Plus 등) `5h 63% · W 88%`처럼 **각각** 나옵니다. [Windows 버전](https://github.com/share-seoi/CCusagebar)의 배터리 이름표와 같습니다.
- 메뉴를 열면 5시간/주간 한도와 초기화 시각을 각각 확인할 수 있습니다.
- Dock 아이콘이나 일반 창을 만들지 않습니다.
- Codex 앱(`com.openai.codex`) 또는 Claude 앱(`com.anthropic.claudefordesktop`)이 실행 중일 때만 메뉴 막대 앱이 켜지고, 둘 다 종료되면 함께 종료됩니다.
- 두 앱이 모두 꺼져 있을 때는 `launchd`의 파일 변경 조건만 등록되어 있으며 감시 프로세스는 상주하지 않습니다.
- Codex 앱이 꺼져 있어도 Claude 앱이 켜져 있으면(Claude에서 Codex CLI를 부르는 경우 등) Codex 로컬 기록을 **1분마다** 확인합니다. 이때 프로세스를 띄우는 계정 조회는 하지 않고, Codex 앱을 켜면 원래대로 20초 확인과 계정 조회로 돌아갑니다.

Codex를 이 Mac에서 사용하면 각 응답 뒤에 값이 갱신되어 최대 20초 안에 메뉴 막대에 반영됩니다.
다른 기기나 Codex 화면과 값이 다를 때는 **지금 새로고침**을 누르면 실시간 계정 값을 다시 읽습니다.

## 동작 방식 (Claude)

- Claude 데스크톱 앱의 로그인 토큰(`config.json`의 `oauth:tokenCacheV2`, 키체인 `Claude Safe Storage`로 복호화)을 **읽기만** 해서, Claude 앱의 사용량 탭과 같은 API(`api.anthropic.com/api/oauth/usage`)로 5시간/주간 사용률과 초기화 시각을 조회합니다. 데스크톱 앱이 켜져 있는 동안 토큰을 갱신하므로 따로 로그인할 필요가 없습니다.
- 데스크톱 토큰이 없거나 만료됐으면 Claude Code가 키체인(`Claude Code-credentials`)에 저장한 토큰을 대신 씁니다.
- Claude 앱이 켜져 있을 때만 조회합니다. Claude가 메뉴 막대에 표시 중이면 1분마다, 아니면 3분마다 조회하고, 앱이 꺼지면 조회를 멈추고 마지막 값을 보여주다가 다시 켜면 바로 조회합니다. Claude 앱으로 전환하거나 메뉴를 열 때 마지막 조회가 20초보다 오래됐으면 바로 다시 조회합니다.
- 토큰을 갱신하거나 키체인에 쓰지 않습니다. 두 토큰이 모두 만료됐으면 Claude가 새로 받을 때까지 아래의 로컬 기록을 대신 사용합니다.
- 조회 제한(HTTP 429)을 받으면 2분부터 최대 15분까지 간격을 늘려 다시 시도합니다.
- 처음 실행하면 macOS가 키체인 접근을 묻습니다(`Claude Safe Storage`, 필요하면 `Claude Code-credentials`). **항상 허용**을 누르면 이후에는 묻지 않습니다. 앱을 다시 빌드하면 서명이 바뀌어 한 번 더 물을 수 있습니다. 거부하면 **지금 새로고침**을 누를 때만 다시 요청합니다.
- 실시간 조회를 쓸 수 없을 때는 Claude 데스크톱 앱이 기록하는 `~/Library/Application Support/Claude/plan-usage-history.json`(약 10~15분 간격)을 사용합니다.

## 코드 구조

- `AppDelegate`: 앱 생명주기, 표시할 앱 선택, 각 모듈 연결을 담당합니다.
- `UsageCoordinator`: 로컬/실시간 값의 우선순위, 캐시, 새로고침 상태를 관리합니다.
- `Log` / `AppInfo`: `~/Library/Logs/CCusagebar/log.txt`에 드문 사건을 남기고, 예전 이름(Codex Usage Bar)의 설정을 처음 한 번 옮겨 옵니다.
- `StatusMenuController`: 메뉴 막대 UI 생성과 표시만 담당합니다. 앱별 메뉴 구역을 따로 둡니다.
- `UsageMonitor` / `LocalUsageStore`: 20초 로컬 기록 추적과 최신 스냅샷 탐색을 담당합니다.
- `ClaudeLiveUsageFetcher`: 키체인 토큰으로 Claude 사용량 API를 조회합니다.
- `ClaudeUsageStore`: 실시간 조회가 안 될 때 Claude 앱의 사용량 기록 파일에서 최신 값을 읽습니다.
- `LiveUsageFetcher`: 사용자가 요청한 Codex 실시간 계정 조회를 한 번 실행합니다.
- `AppLifecycle` / `ProviderIconLoader`: Codex·Claude 실행/활성화 감지와 아이콘 로딩을 각각 담당합니다.

## 빌드

Codex 또는 ChatGPT macOS 앱이 `/Applications`에 설치된 상태에서:

```bash
./scripts/build-app.sh
./scripts/install-lifecycle.sh
```

생성 위치: `dist/CCusagebar.app`

설치 위치: `~/Applications/CCusagebar.app`

설치 스크립트는 `~/Library/LaunchAgents/local.mackim.CCusagebar.lifecycle.plist`를 등록합니다. 예전 이름의 `local.mackim.CodexUsageBar.lifecycle.plist`와 `Codex Usage Bar.app`이 있으면 먼저 제거합니다. 로그인할 때 한 번 상태를 확인하고, 이후 Codex의 `SingletonLock` 생성/삭제와 Claude 앱 지원 폴더 변경을 시작 조건으로 사용합니다.

### 코드 서명

`build-app.sh`는 로그인 키체인에 `CodexUsageBar Local Code Signing` 인증서가 있으면 그것으로 서명합니다(예전 이름 그대로인 인증서를 계속 씁니다). 서명이 빌드마다 바뀌지 않으므로 Claude 키체인 항목의 **항상 허용**이 다시 빌드해도 유지됩니다. 인증서가 없으면 임시 서명을 사용하고, 이 경우 빌드할 때마다 키체인 허용을 다시 묻습니다. 다른 인증서를 쓰려면 `CODESIGN_IDENTITY` 환경 변수로 이름을 지정합니다.

인증서는 이 Mac에서만 쓰는 자체 서명(10년 유효, 코드 서명 전용)이며, 시스템 신뢰 설정은 바꾸지 않았습니다. 새 Mac에서 다시 만들려면:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 \
  -subj "/CN=CodexUsageBar Local Code Signing" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem \
  -name "CodexUsageBar Local Code Signing" -out id.p12 -passout pass:temp
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P temp -T /usr/bin/codesign
rm -P key.pem id.p12 cert.pem
```

자동 실행 조건만 제거하려면:

```bash
./scripts/uninstall-lifecycle.sh
```

## 진단

메뉴 UI 없이 현재 값을 한 번 확인할 수 있습니다.

```bash
.build/release/CCusagebar --print-usage
.build/release/CCusagebar --print-live-usage
.build/release/CCusagebar --print-claude-usage
.build/release/CCusagebar --print-claude-live-usage
```
