# PLAN (macOS) — T-333 전체 MCP 공급자 자동/수동 OAuth 병행 (3분 초안)

> T-328(수동 전환) 확대 — 전환이 아니라 **전 공급자 양쪽 지원**. 기준일: 2026-09-05

## 현상
- 템플릿당 authMode 1개 고정: Linear/GitHub=수동만, 나머지 DCR만.
- 수동 폼은 템플릿 내장 엔드포인트만 사용, DCR 템플릿은 수단 없음.
- 토큰 갱신(`MCPProviderManager.refreshToken`)은 항상 issuer 재발견 — 수동
  커스텀 엔드포인트 무시 (GitHub 등 갱신 실패 원인).

## 변경
1. `MCPProviderConfiguration` += `customAuthorizationEndpoint`·`customTokenEndpoint`
   (decodeIfPresent — 구저장 호환).
2. 템플릿에 검증된 수동 엔드포인트 기입 (GitLab·Notion·Slack·Atlassian — 당일 대조,
   나머지는 nil → 사용자 입력).
3. 연결 화면: OAuth 템플릿에 [자동|수동] 세그먼트 (기본값=템플릿). 수동 폼에
   Authorize/Token URL 필드 추가 (템플릿값 프리필, 편집 가능).
4. 수동 연결 시 `config.authMode = .oauth21Manual` 명시 + 커스텀 엔드포인트 저장.
   엔드포인트 결정은 순수 헬퍼 `resolveOAuthEndpoints`로 분리 (테스트 가능).
5. 갱신 경로: `customTokenEndpoint` 우선, 없으면 기존 재발견.
6. 서비스(`authenticate`)는 엔드포인트 유무 분기 그대로 — 변경 없음.

## 검증
- 신규 `MCPOAuthEndpointTests` (결정 헬퍼: 커스텀 우선·템플릿 폴백·둘 다 없음).
- 전체 unit + `./build_and_run.sh debug macos`. 실연결은 사용자 (키/콘솔 필요).

## DoD
- 빌드·테스트 통과, TODO·CHANGELOG·세션 로그. T-328은 본 건으로 흡수 표기.
