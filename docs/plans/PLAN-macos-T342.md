# PLAN (macOS) — T-342 wigolo 기본 내장 MCP (A안 + 기본 켜기) (3분 초안)

## 범위
- `MCPServerEditSheet` presets에 `wigolo` 1줄 추가 (수동 선택 유지)
- `MCPServerStore.init` 최초 1회 wigolo 시드 (`isEnabled=true`, 고정 UUID, 마이그레이션 플래그 `mcpSeedVersion=1`)
- 신규 `MCPExecutableResolver.swift`: `npx/uvx/node` 절대경로 탐색 → `MCPConnection.launchProcess` 적용 (시드 성패의 선행 조건)
- 로그·에러코드(`E-MAC-MCP-1001`)·`error_message_ko.json` 갱신

## 제외
- Tavily 백엔드 교체(C안), 카탈로그 원격 템플릿, research 합성용 LLM 키 설정

## 변경 파일
1. `AIModelTalk/Services/MCPExecutableResolver.swift` (신규)
2. `AIModelTalk/Services/MCPModels.swift` (시드 + `wigoloSeedID`)
3. `AIModelTalk/Services/MCPConnection.swift` (`launchProcess`에서 resolve)
4. `AIModelTalk/Views/MCPSettingsView.swift` (presets 1줄)
5. `AIModelTalkTests/MCPWigoloSeedTestsV41.swift` (신규 테스트)
6. `error_message_ko.json` (`E-MAC-MCP-1001`)
7. `docs/CHANGELOG.md` (T-342 항목)

## 동작 정의
- 신규: 첫 실행 시 wigolo(enabled) 1건 자동 등록 → 도구 지원 모델 전송 시 연결 시도 → 권한 기본 `.ask`
- 기존: `mcpSeedVersion` 없으면 id 기준 upsert-if-missing 1회, 사용자 기존 설정 보존
- 실패: npx 미발견·Node 없음 → 상태 failed + `E-MAC-MCP-1001` 로그, 앱 크래시 없음

## 검증
- 신규 테스트만 실행 (`-only-testing`), 빌드 → `build_and_run.sh debug macos` → DebugPanel ERROR 0
