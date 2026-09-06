<div align="center">

# AIModelTalk

**무료 AI 모델로 대화하는 macOS 네이티브 채팅 앱**

NVIDIA · OpenRouter · Groq · Gemini + 커스텀(OpenAI 호환) 공급자의 무료 모델을
하나의 채팅 UI에서 자유롭게 사용하세요.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B_(Sonoma)-9cf) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue) ![License](https://img.shields.io/badge/License-MIT-green) ![CI](https://github.com/BoraSarang/AIModelTalk/actions/workflows/ci.yml/badge.svg)

**[🌐 웹사이트](https://borasarang.github.io/AIModelTalk/) · [⬇️ 최신 릴리즈](https://github.com/BoraSarang/AIModelTalk/releases/latest)**

**v0.1.0** — 신규 출발

</div>

---

## ✨ 소개

AIModelTalk은 **무료 모델 전용** macOS 네이티브 앱입니다. 여러 무료 공급자를 한 화면에서 비교하고, 카카오톡 스타일 말풍선과 네이티브 Markdown 렌더러로 대화할 수 있습니다.

유료 모델은 표시하지 않습니다. 로컬 실행 속도와 안정성을 위해 네이티브 SwiftUI로 만들어졌습니다.

## 🚀 주요 기능

- 카카오톡 스타일 말풍선 + 네이티브 Markdown 렌더러, 스트리밍 (⌘⇧B 벤치마크 · ⌘⇧C 비교)
- 무료 전용 모델 디렉토리 + 공급자별 런타임 갱신, 키는 Keychain 관리
- 세션 관리(제목 자동 생성·저장/복원·대화 분기) · 전역 검색(⌘⇧F)
- 전역 장기 메모리(대화 자동 추출 → 모든 대화에 주입) · 보관함/휴지통
- 퀵챗 · 인코그니토 · 웹 검색 · wigolo MCP 기본 내장
- 스킬 로더(4소스) · MCP 도구(stdio/HTTP, 권한 게이트) · 아티팩트 프리뷰
- 글로벌 단축키 + 선택 텍스트 캡처

## 🔑 공급자

| 공급자 | 키 관리 | 무료 모델 |
|--------|---------|-----------|
| **NVIDIA** | 키체인 자동 감지 | GPT-OSS-20B 등 |
| **OpenRouter** | 수동 입력 | `:free` 계열 |
| **Groq** | 수동 입력 | 무료 티어 |
| **Gemini** | 수동 입력 | Flash 무료 티어 |
| **커스텀** | URL 직접 입력 | 사용자 지정 (OpenAI 호환) |

## 💾 설치

### 릴리즈 다운로드 (권장)

[최신 릴리즈](https://github.com/BoraSarang/AIModelTalk/releases/latest)에서 `AIModelTalk.zip`을 받아 `~/Applications`에 넣으세요.

> 서명되지 않은 앱이라 첫 실행 시 Gatekeeper 경고가 뜰 수 있습니다.
> 우클릭 → 열기 → 열기를 누르거나, 터미널에서 아래 명령을 실행하세요.
>
> ```bash
> xattr -d com.apple.quarantine ~/Applications/AIModelTalk.app
> ```

### 직접 빌드

요구 사항: macOS 14+, Xcode, [xcodegen](https://github.com/yonaskolb/XcodeGen)

```bash
# xcodegen 프로젝트 생성 → 빌드 → ~/Applications에 설치 → 실행
./build_and_run.sh debug macos

# 또는 수동으로
xcodegen generate --spec project.yml
xcodebuild -project AIModelTalk.xcodeproj -scheme AIModelTalk -configuration Debug build
```

## 🏗️ 프로젝트 구조

```
AIModelTalk/
├── project.yml            # xcodegen 스펙 (버전 0.1.0)
├── build_and_run.sh       # 빌드 디스패처
├── site/                  # 랜딩 페이지 (GitHub Pages)
├── .github/workflows/     # CI · Pages · 릴리즈
├── AIModelTalk/           # 앱 소스
│   ├── Core/              # 로거 · 설정 · 핫키 · 키체인 · 텍스트 캡처
│   ├── Models/            # 말풍선 · 세션 · 모델 · 전역 메모리
│   ├── Providers/         # OpenAI 호환 · Gemini · Anthropic 클라이언트
│   ├── Services/          # 모델 카탈로그 · 벤치마크 · 비교 · 스킬 · MCP
│   ├── ViewModels/        # ChatViewModel
│   └── Views/             # 채팅 · 말풍선 · 마크다운 · 설정 · 디버그패널
├── AIModelTalkTests/      # XCTest
├── docs/                  # PRD · DESIGN · TODO · CHANGELOG
└── error_message_ko.json  # 사용자 메시지 매핑
```

## 📚 문서

| 문서 | 설명 |
|------|------|
| [PRD](docs/PRD.md) | 제품 요구사항 · 타겟 사용자 · 기능 |
| [DESIGN](docs/DESIGN.md) | 아키텍처 · 데이터 모델 · 디자인 시스템 |
| [TODO](docs/TODO.md) | 작업 추적 |
| [CHANGELOG](docs/CHANGELOG.md) | 변경 기록 |

## ⚖️ 라이선스

[MIT](LICENSE) © BoraSarang
