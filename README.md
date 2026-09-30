# CCusagebar (mac)

**메뉴 막대에 한 줄. Codex·Claude 남은 사용량을 한눈에.**

> Windows를 쓰시나요? 작업표시줄 배터리 버전은 **[CCusagebar (Windows)](https://github.com/share-seoi/CCusagebar)** 에 있습니다.

<p align="center">
  <img src="docs/images/menubar-claude.png" alt="Claude를 쓰는 중: 메뉴 막대에 5h 90% · W 95%" width="290"><br>
  <sub>Claude를 쓰는 중</sub>
</p>

지금 쓰고 있는 앱의 남은 한도를 메뉴 막대에 보여줍니다. **Codex를 앞에 띄우면 Codex, Claude를 띄우면 Claude 사용량으로 자동으로 바뀌고**, 다른 앱으로 넘어가면 마지막 표시를 그대로 둡니다.

한도마다 `5h`(5시간 한도)·`W`(주간 한도) 이름표가 붙습니다. 계정에 한도가 둘이면(Claude, Codex Plus 등) `5h 63% · W 88%`, 주간 한도만 있으면 `W 88%`로 나옵니다.

둘 다 계속 보고 싶으면 메뉴에서 **Codex·Claude 둘 다 표시**(⌘B)를 켜세요. 메뉴 막대 항목 하나 안에 `[Codex] W 96%   [Claude] 5h 77% · W 83%`처럼 나란히 뜹니다. 메뉴 막대가 꽉 찬 노치 Mac에서도 숨지 않습니다.

항목을 누르면 두 계정의 한도와 초기화 시각이 함께 나옵니다.

## 설치 (macOS 13 이상)

터미널에서:

```bash
git clone https://github.com/share-seoi/CCusagebar-mac.git
cd CCusagebar-mac
./scripts/build-app.sh
./scripts/install-lifecycle.sh
```

- Swift로 빌드하므로 Xcode 명령행 도구가 필요합니다. 없으면 `xcode-select --install`로 설치하세요.
- `~/Applications/CCusagebar.app`에 설치됩니다. Codex나 Claude 앱을 열면 자동으로 켜지고, 둘 다 닫으면 꺼집니다.
- 예전 이름(`Codex Usage Bar.app`)으로 설치돼 있었다면 설치 스크립트가 걷어내고, 마지막 사용량·표시 설정은 새 앱이 처음 켜질 때 옮겨 옵니다.
- 처음 실행하면 macOS가 Claude 로그인 정보가 든 키체인 접근을 묻습니다. **항상 허용**을 누르면 다시 묻지 않습니다. 코드 서명, 진단 옵션 등 자세한 내용은 [상세 안내](docs/macos.md)를 보세요.

## 사용법

1. Codex 또는 Claude 데스크톱 앱에 평소처럼 로그인해 둡니다.
2. 둘 중 하나를 열면 메뉴 막대에 사용량이 나타납니다.
3. 항목을 누르면 두 앱의 한도 카드와 **지금 새로고침**, **Codex·Claude 둘 다 표시**, **CCusagebar 종료**가 나옵니다.

## 어떻게 읽어 오나요

- **Codex:** 로컬 세션 기록을 20초마다 확인하고, 시작·새로고침 때와 Codex로 전환할 때(1분에 한 번까지) Codex 앱 서버로 계정 한도를 조회합니다. Codex 앱이 꺼져 있어도 Claude 앱이 켜져 있으면(Claude에서 Codex CLI를 부르는 경우 등) 로컬 기록을 1분마다 확인합니다.
- **Claude:** Claude 데스크톱 앱의 로그인 토큰을 **읽기만** 해서 사용량 API를 조회합니다. 메뉴 막대에 Claude가 표시 중이면 1분, 아니면 3분 간격이고, Claude로 전환하거나 메뉴를 열면 바로 새로 받아옵니다. 모델 추론은 요청하지 않습니다.
- 토큰을 복사·수정·전송하지 않으며, 저장소에도 계정 정보는 들어 있지 않습니다.
- 시작·종료·앱 실행/종료·연결 상태 전환 같은 드문 사건만 `~/Library/Logs/CCusagebar/log.txt`에 남깁니다(최대 256KB, 넘으면 `log.old.txt`로 돌림). 토큰이나 응답 본문은 기록하지 않습니다.

## 제거

1. 저장소 폴더에서 `./scripts/uninstall-lifecycle.sh`를 실행해 자동 실행을 해제합니다.
2. 메뉴에서 **CCusagebar 종료**를 누른 뒤 `~/Applications/CCusagebar.app`을 지웁니다.
3. 기록까지 지우려면 `~/Library/Logs/CCusagebar` 폴더를 지웁니다.

## 참고

- 개인이 만든 비공식 도구이며 OpenAI, Anthropic과 관계가 없습니다.
- 사용량 조회에 쓰는 API는 공개적으로 보장된 API가 아니어서, 앱이 업데이트되면 동작이 바뀔 수 있습니다.
- 에이전트(Codex, Claude Code 등)에게 설치를 맡길 때는 [AGENTS.md](AGENTS.md)를 읽게 하면 됩니다.
- 이 저장소의 예전 이름은 `CodexUsageBar`입니다. Windows 버전은 [CCusagebar](https://github.com/share-seoi/CCusagebar)로 옮겨졌습니다.

## 라이선스

[MIT](LICENSE)
