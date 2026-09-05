# PLAN v0.3.3 (macOS) — T-331 검증된 무료 모델 카탈로그 반영 (3분 초안)

> 기준일: 2026-09-05 · 범위: 무료만 (유료 제외 확정)

## 검증 원천 (구현 당일 대조)
- Zen: `opencode.ai/docs/zen` — 무료 6종 확정: big-pickle, mimo-v2.5-free,
  ling-3.0-flash-fin-free, nemotron-3-ultra-free, nemotron-3.5-lightning-free,
  muse-spark-1.3-contributor-free. 주의: Muse Spark는 문서상 `/responses`
  엔드포인트 — 앱의 chat/completions 직결은 실기동 확인 필요.
- OpenRouter: `/api/v1/models` — `:free` 19종, ID·context_length 확정
  ( laguna-s-2.1 262144, ultra-550b 1M, lightning 1M, m3 1M, m2.7 196608,
  inkling 1M, north-mini-code 256000, glm-5.2 256000 등 ).
- NIM: 키 없이 검증 불가 → 정적 추가 없음 (NVIDIA refresh에 위임).

## 변경
1. `ModelCatalog.defaultModels` — 사망 OR 4종 제거
   (gemini-2.5-flash-preview/deepseek-v3-0324/llama-4-maverick/qwen3-235b,
   모두 `:free` 목록에서 소멸), OR 무료 15종 + Zen 3종 추가.
2. `fallbackPriority` — MuseSpark(Zen) → NorthMiniCode(OR) → Ultra(Zen) →
   gpt-oss-20b(NVIDIA) → Gemini 3.6 Flash. 테스트 동기 수정.
3. `codingPreferredIDs` — 검증 무료 코딩 ID 정식 ID로 추가 (기존 유료 유지).
4. `supportsVision` — mimo·inkling·nano-omni·minimax-m3 추가.

## 검증
- `xcodebuild test` (FreeFallbackCandidatesTestsV33 동기 수정분 포함)
- `./build_and_run.sh debug macos` + 설정 모델 목록 노출 확인 (AX 조작 금지 — 실기동은 사용자)

## DoD
- 빌드 성공, 테스트 통과, TODO·CHANGELOG·세션 로그 갱신.
- Muse Spark `/responses` 이슈는 CHANGELOG에 "실기동 확인 필요"로 명시.
