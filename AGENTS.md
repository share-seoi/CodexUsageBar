# CCusagebar (mac) 작업 안내

이 저장소는 Codex·Claude의 남은 계정 사용량을 macOS 메뉴 막대에 보여주는 작은 도구입니다. Windows 버전은 별도 저장소 [share-seoi/CCusagebar](https://github.com/share-seoi/CCusagebar)에 있습니다.

## 사용자가 다른 Mac에 설치해 달라고 할 때

1. 현재 OS를 확인합니다. Windows라면 이 저장소가 아니라 [CCusagebar](https://github.com/share-seoi/CCusagebar)의 안내를 따릅니다.
2. macOS 13 이상이고 Xcode 명령행 도구(`swift`)가 있어야 합니다. 없으면 사용자에게 `xcode-select --install`을 안내합니다.
3. 저장소 루트에서 아래를 실행합니다.

   ```bash
   ./scripts/build-app.sh
   ./scripts/install-lifecycle.sh
   ```

4. 설치 위치는 `~/Applications/CCusagebar.app`이고, `~/Library/LaunchAgents/local.mackim.CCusagebar.lifecycle.plist`가 Codex/Claude 앱이 켜질 때 메뉴 막대 앱을 띄웁니다. 두 앱이 모두 꺼져 있으면 메뉴 막대 앱도 곧 종료되므로, 프로세스가 없다는 이유만으로 설치 실패라고 말하지 않습니다.
5. 예전 이름(`Codex Usage Bar.app`, `local.mackim.CodexUsageBar.lifecycle`)이 있으면 설치 스크립트가 제거합니다. Codex나 Claude 프로세스는 종료하지 않습니다.

## 계정 연결과 검증

- 사용자 본인이 그 Mac의 Claude/Codex 앱에 로그인해야 합니다. 다른 기기의 토큰이나 설정 파일을 복사하거나 Git에 넣지 않습니다.
- Claude는 데스크톱 앱 토큰(키체인 `Claude Safe Storage`로 복호화)을 읽기만 하고, 없거나 만료됐으면 Claude Code 키체인 토큰을 씁니다. 토큰을 갱신하거나 키체인에 쓰지 않습니다. 첫 실행 때 키체인 접근 창이 뜨면 사용자가 직접 허용해야 합니다.
- Claude는 메뉴 막대에 표시 중이면 1분, 아니면 3분마다 조회합니다. 토큰별 HTTP 429 제한이 있으므로 간격을 줄이지 않습니다.
- Codex는 20초마다 로컬 기록을 읽고, 시작·수동 새로고침·Codex로 전환할 때(1분에 한 번까지) App Server에서 계정 한도를 조회합니다. 조회마다 프로세스를 띄우므로 주기 조회는 넣지 않습니다.
- 코드만 검증할 때는 `swift test`를 실행합니다. 실제 계정 값은 `.build/release/CCusagebar --print-live-usage`, `--print-claude-live-usage` 등으로 확인합니다([상세 안내](docs/macos.md#진단)). 빌드 성공과 실제 계정 조회 성공을 구분해 보고합니다.
- 동작 기록은 `~/Library/Logs/CCusagebar/log.txt`에 있습니다. 문제를 볼 때 먼저 확인합니다.

## 수정 시 규칙

- 사용자의 실행 중인 다른 프로그램, 인증 정보, 자동 실행 설정, 관계없는 변경을 보존합니다.
- 변경 후 `swift test`와 `./scripts/build-app.sh`를 실행합니다.
- 로그에는 드문 사건만 남기고 토큰, HTTP 본문, 개인 정보는 넣지 않습니다.
- `.build`와 `dist`는 빌드 산출물이며 Git에 추가하지 않습니다. 계정 진단 결과, 토큰, 로컬 사용량 캐시도 커밋하지 않습니다.
