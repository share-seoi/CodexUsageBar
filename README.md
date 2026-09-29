# Codex Usage Bar

**작업표시줄에 배터리 하나. Codex·Claude 남은 사용량을 한눈에.**

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/hero-dark.png">
    <img src="docs/images/hero-light.png" alt="작업표시줄의 배터리 위젯과, 클릭하면 열리는 Codex·Claude 사용량 상세 창" width="720">
  </picture>
</p>

지금 쓰고 있는 앱(Codex 또는 Claude)의 남은 한도를 작업표시줄에 배터리로 보여줍니다. 누르면 두 계정의 한도와 초기화 시각이 함께 나옵니다. 그게 전부입니다.

| Codex (주간 한도 1개) | Claude (5시간 + 주간) |
| :---: | :---: |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/widget-codex-dark.png"><img src="docs/images/widget-codex-light.png" alt="Codex 위젯" height="48"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/widget-claude-dark.png"><img src="docs/images/widget-claude-light.png" alt="Claude 위젯" height="48"></picture> |

## 설치 (Windows 10/11)

PowerShell에서:

```powershell
git clone https://github.com/share-seoi/CodexUsageBar.git
cd CodexUsageBar
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\install.ps1
```

- 관리자 권한, .NET SDK, Node, Python 모두 필요 없습니다. Windows에 기본으로 있는 .NET Framework 4.8로 소스에서 바로 빌드합니다.
- `%LOCALAPPDATA%\Programs\CodexUsageBar`에 설치되고 바로 실행됩니다.
- 로그인할 때 자동으로 켜지게 하려면 명령 끝에 `-AutoStart`를 붙이거나, 위젯 상세 창의 **자동 시작** 버튼을 누르세요.
- 설치 전에 코드를 확인하고 싶다면 `.\windows\test.ps1`을 먼저 실행하세요. 네트워크 없이 합성 데이터로 동작을 검사합니다.

## 사용법

1. Codex 또는 Claude 데스크톱 앱에 평소처럼 로그인해 둡니다.
2. 둘 중 하나를 열면 작업표시줄에 배터리가 나타납니다. 둘 다 닫으면 위젯도 숨습니다.
3. 배터리를 누르면 상세 창이 열립니다: **새로고침**, **자동 시작** 켜기/끄기, **종료**.

한도가 여러 개인 계정은 `5h`·`W` 이름표를 붙인 배터리가 나란히 표시되고, 남은 양이 적으면 빨갛게 바뀝니다.

## 어떻게 읽어 오나요

- **Codex:** 로컬 세션 기록을 20초마다 확인하고, 시작·새로고침 때 Codex 앱 서버로 계정 한도를 한 번 조회합니다.
- **Claude:** 이 PC에 저장된 Claude 로그인 토큰을 **읽기만** 해서 20초마다 사용량 API를 조회합니다. 모델 추론은 요청하지 않습니다.
- 토큰을 복사·수정·전송하지 않으며, 저장소에도 계정 정보는 들어 있지 않습니다. 설치하는 사람의 PC에 로그인된 계정이 표시됩니다.

자세한 동작과 진단 옵션은 [Windows 안내](windows/README.md)를 참고하세요.

## 제거

1. 자동 시작을 켰다면 위젯 상세 창에서 먼저 끕니다.
2. 상세 창에서 **종료**를 누릅니다.
3. `%LOCALAPPDATA%\Programs\CodexUsageBar`(프로그램)와 `%LOCALAPPDATA%\CodexUsageBar`(마지막 사용량 캐시) 폴더를 지웁니다.

## macOS

메뉴 막대 버전도 있습니다. 빌드와 설치는 [macOS 안내](docs/macos.md)를 보세요.

## 참고

- 개인이 만든 비공식 도구이며 OpenAI, Anthropic과 관계가 없습니다.
- 사용량 조회에 쓰는 API는 공개적으로 보장된 API가 아니어서, 앱이 업데이트되면 동작이 바뀔 수 있습니다.
- 에이전트(Codex, Claude Code 등)에게 설치를 맡길 때는 [AGENTS.md](AGENTS.md)를 읽게 하면 됩니다.

## 라이선스

[MIT](LICENSE)
