# PRD — AIModelTalk (macOS)

## 개요
무료 AI 모델로 대화하는 macOS 네이티브 채팅 앱. NVIDIA, OpenRouter, Groq, Gemini 무료 모델 + 커스텀(OpenAI 호환) 공급자를 하나의 채팅 UI에서 사용.

- 버전: **0.1.0** (신규 출발)
- 플랫폼: macOS (SwiftUI, 최소 macOS 14)
- 빌드: XcodeGen(`project.yml`) → `build_and_run.sh debug macos`

## 타겟 사용자
- AI 모델을 무료로 체험하고 싶은 개발자/일반 사용자
- 여러 모델을 비교하며 성능을 테스트하고 싶은 사용자

## 핵심 기능
| 영역 | 설명 |
|------|------|
| 대화창 | 카카오톡 스타일 말풍선 + 네이티브 Markdown 렌더러, 스트리밍 |
| 모델 디렉토리 | 무료 전용 모델 목록 + 공급자별 런타임 갱신 |
| 키 관리 | Keychain 저장 + 공급자별 자동 감지/수동 입력 |
| 설정 | 공급자/일반/모델/단축키/스킬/MCP 탭 |
| 세션 관리 | 제목 자동 생성, 저장/복원, 대화 분기(fork) |
| 보관함 · 휴지통 | 대화 보관/해제, 휴지통 30일 자동 비우기·복원·영구 삭제 |
| 장기 메모리 (전역) | 대화에서 사실 자동 추출 → 앱 전역 기억으로 저장, 모든 대화에 관련도 검색으로 주입 |
| 전역 검색 | 세션·메시지 통합 검색 (⌘⇧F) |
| 벤치마크 | TTFT/총 시간 측정 리더보드 (⌘⇧B) |
| 비교 모드 | 병렬 응답 + 판정 요약 (⌘⇧C) |
| 글로벌 단축키 | Ctrl+Space / Ctrl+Shift+Space + 선택 텍스트 캡처 |
| 퀵챗 | 빠른 질문 창, 인코그니토(기억 미사용) 모드 |
| 웹 검색 | 검색 결과를 컨텍스트로 첨부 |
| 스킬 | opencode·claude·alma·프로젝트 4소스 로드, 우선순위 병합, 출처 배지 |
| MCP 도구 | stdio / Streamable HTTP 서버 연결, 도구 호출 루프, 권한 게이트 |
| 아티팩트 프리뷰 | html/svg/mermaid/react 코드펜스 미리보기 + 파일 저장 |

## 공급자
| 공급자 | 키 관리 | 무료 모델 |
|--------|---------|-----------|
| NVIDIA | 키체인 자동 감지 | GPT-OSS-20B 등 |
| OpenRouter | 수동 입력 | `:free` 계열 |
| Groq | 수동 입력 | 무료 티어 |
| Gemini | 수동 입력 | Flash 무료 티어 |
| 커스텀 | URL 직접 입력 | 사용자 지정 |

## 비고
- 무료 모델 전용 (유료 모델은 표시하지 않음)
- 판정 요약은 설정 on/off 옵션
- 스킬 소스: `~/.opencode/skills` > `~/.claude/skills` > `~/.config/alma/skills` > `{프로젝트}/.alma/skills` — 동일 ID는 고우선순위 유지
- MCP 도구는 설정에서 on/off, 서버별 권한 정책 저장
- 아티팩트 프리뷰는 sandbox(allow-scripts) iframe으로 격리