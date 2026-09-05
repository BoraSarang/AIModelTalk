# PLAN v0.3.2 — 토큰 상태 표시 (macOS)

- **목표**: 기존 축2 비용(USD) 표시 전면 제거 + 채팅 하단(입력바 우측)에 선택 모델의 **실제 토큰 사용/남음 상태** 배지(오소러스식) + 설정 **토큰 상태** 탭(사용 중 공급자/모델만).
- **결정**: (1) 모델 탭 가격 편집 + 카탈로그 가격 필드 제거 (2) 계정 풀은 Anthropic 헤더 실측, 그 외는 모델 컨텍스트 대비 표시. 우선순위: 계정 풀 → 모델 컨텍스트.
- **1커밋 1관심사**: 비용 제거 → 토큰 데이터 → 배지/팝오버 → 설정 탭.

## 1. 비용 제거 (축2 롤백)
- `ChatModels.swift`: `ChatMessage.costUSD`, `SessionCost`, `AIModel.inputPricePerM/outputPricePerM`, `isPaid` 삭제 (`isFree`·`contextLimit` 유지)
- `ModelCatalog.swift`: 유료 모델 가격 인자 제거
- `ModelsSettingsView.swift`: 가격 편집 시트/가격 컬럼 제거
- `BubbleViews.swift`: 말풍선 실비용 라벨 제거 (토큰 `↑↓` 배지는 유지)
- `CostSettingsView.swift` 파일 삭제 → `TokenStatusSettingsView` 교체
- `SettingsView.swift`: 탭명 `비용/토큰`→`토큰 상태`, 아이콘 `tuningfork`
- 테스트: `isPaid` 참조 생성자 시그니처 정리

## 2. 토큰 데이터 — `Services/TokenQuota.swift` 신규
- `ModelTokenSnapshot`: 현재 세션에서 선택 모델과 동일 provider+modelID인 메시지 실측 누적(prompt/completion) vs `contextLimit`. 실측 0이면 `TokenEstimator.estimateConversation` 폴백(추정). → `used/limit/remaining/ratio/source(.measured/.estimated)`
- `ProviderAccountQuota`: 공급자 응답 헤더 기반 잔량. `limit/remaining/usage/updatedAt`
- `TokenQuotaStore.shared`: 계정 잔량 보관 + 캡처 헤더 파싱(`x-ratelimit-limit-tokens`/`x-ratelimit-remaining-tokens`/`x-ratelimit-usage-tokens`)
- 우선순위: 계정 잔량(공급자 풀) 존재 시 계정 기준 → 없으면 모델 컨텍스트

## 3. Anthropic 헤더 캡처
- `AnthropicClient.swift:102` (및 216) `HTTPURLResponse`에서 `x-ratelimit-*` 추출 → `TokenQuotaStore.capture(from:)` 호출

## 4. 채팅 하단 배지 (+팝오버)
- `ChatInputBarView.swift` `tokenMeter`(155행) 대체:
  - 배지: `남음 136.6K 토큰` + 비율색(>0.9 레드 / >0.7 오렌지 / else secondary), 컨텍스트 초과 경고 유지
  - 클릭/호버 팝오버: 모델·공급자 / 한도 / 실측 ↑↓(또는 추정) / 사용·남음 게이지 / 계정 잔량(해당 시) / 갱신 시각
- 리렌더: `@Published selectedModel` + `tokenTick` 구독으로 모델 변경·실측 갱신 자동 반영

## 5. 설정 토큰 상태 탭 — `Views/TokenStatusSettingsView.swift`
- 필터: API 키 설정된 공급자(AppSettings) + 로컬(Ollama/Apple Intelligence) + 활성 모델(visibleModels)
- 행: 공급자 배지 · 모델명/ID · 한도 · 실측 ↑↓ / 추정 · 사용/남음 막대 · 계정 잔량(있을 때)

## 6. 검증 게이트
- `./build_and_run.sh debug macos` → AX/픽셀: 배지 표시·모델 변경 리플렉션·설정 탭 전환 → 사용자 캡처 확인
- 로그: TokenQuota 캡처 `[INFO] [TOKEN]`, 실패 경로 에러코드 `E-MAC-*`

---

# 부록 — MCP 설정 UI 수정 (T-324~326, 사용자 보고 후)

사용자 보고(다크 모드): ① 연결 시트/카드의 글자가 안 보임 ② "공급자 상태 0/2 연결됨·활성 도구·전체 공급자" 요약이 카드와 겹쳐 보임 ③ Linear 공급자가 2개(중복).

- **원인(확정)**: `GradientButton`(GradientButton.swift:42)이 배경=`theme.accentColor`, 글자=`.white` 고정. DarkTheme `accentColor=#f5f5f0`(흰색) → **흰 배경+흰 글자**. Light는 `#1a1a18`(검정)이라 라이트에서만 정상.
- **T-324 `GradientButton` luminance 복구(전역)**: 배경색 밝기(`NSColor` luminance) 기반 전경 자동 반전 + 로딩 스피너 tint 동일 처리. `Color.luminance` extension은 `Theme.swift`에 추가.
- **T-325 헬스바 → 섹션 헤더 병합**: `MCPSettingsView.remoteSection`의 별도 `healthSnapshotCard`(공급자 상태/활성 도구/전체 공급자) 제거 → "원격 MCP 공급자" 헤더줄에 소형 요약 `0/2 연결됨 · 도구 0개 · 전체 2` 병합. (사용자 선택)
- **T-326 중복 재발 방지**: `MCPProviderConnectView.connectOAuth()`에서 `fromTemplate()`(새 UUID) 생성 전, `MCPProviderStore.providers`에서 동일 `templateID` + 정규화된 `url` 기존 항목을 찾아 그 `id` 재사용 → `upsert`가 기존 항목에 토큰/상태 갱신. 기존 "Linear 2개" 데이터는 **사용자 수동 정리**(코드에서 미삭제).
- 검증: 빌드 → MCP 탭 AX(요약 문구 위치·카드 수) → 연결 시트 열어 GradientButton 색 확인(픽셀).

## 문서
- `docs/TODO.md` T-321~326 + `docs/CHANGELOG.md` v0.3.2