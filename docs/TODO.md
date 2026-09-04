# TODO — AIModelTalk v0.2.5

v0.2.5 "Osaurus 스타일 테마 인프라 & 컴포넌트 라이브러리". 상세: `docs/plans/PLAN_v0.2.5_macos.md`.
범위 확정: 테마 시스템(Light/Dark/Custom) + 20+ 컴포넌트 라이브러리 + 글라스 지원 + 마스코트 캐릭터.

## 진행 중

(없음 — v0.2.5 완료)

## 백로그

- [ ] T-320 코드 블록 Splash SPM 연동 (선택 — regex 폴백 사용 중)

## 완료 (v0.2.5)

- [x] Phase 1: 테마 인프라 구축 — ThemeProtocol(50+ 토큰), LightTheme/DarkTheme, ThemeBox(@dynamicMemberLookup), ThemeManager, CustomTheme, ThemeConfigurationStore, DesignSystem 호환 레이어 (2026-09-04)
- [x] Phase 2: 공통 컴포넌트 22개 — MinimalCard, GradientButton, FittedSheetFrame, GlassBackground, AnimatedTabSelector, CodeBlockView, FloatingInputCard, EmptyStateView, ToastManager 등 (2026-09-04)
- [x] 빌드 에러 15건 수정 — environment key, 중복 struct, model property, animation var/func 통일 (2026-09-04)
- [x] Phase 3-1: SettingsView → .formStyle(.grouped) + theme environment + minHeight: 520 (2026-09-05)
- [x] Phase 3-2: MCPSettingsView → ProviderCard 2열 그리드 + 헬스 스냅샷 카드 (2026-09-05)
- [x] Phase 3-3: MCPProviderConnectView → 테마 컴포넌트 + 단계 표시기 (2026-09-05)
- [x] Phase 3-4: ChatSession.themeID?: String 세션별 테마 지원 (2026-09-05)
- [x] CharacterIllustrations SF Symbol 폴백 적용 (2026-09-05)

## 완료 (v0.2.3까지)

- [x] v0.2.3 병렬 비교 UX 개선 — `CompareSelectorView` 분리·선택 하이라이트·Diff/합성/프롬프트 마크다운·Diff 창 900×520 (2026-09-04, 690365d)
- [x] v0.2.2 모델 팝업·설정 멈춤 근본 해결 — init O(N²) 제거 + 활성 인덱스 캐시 (2026-09-03, d363630)
- [x] v0.2.1 기본 모델 개념 제거 — 모든 모델 기본 해제 (2026-09-03, 47324c1)
- [x] T-201 대화 내 병렬 멀티모델 비교 (뷰A) — 나란히 그리드·래인 채택 (2026-09-03)
- [x] T-202 캐릭터별 온도 전달 (2026-09-03)
- [x] EOL(410)/모델없음(404) 모델 자동 비활성화 + Gemini 턴 보정 (2026-09-03, b584ab8)
- [x] 비교 UX 개선 — 모델 토글 선택/오버레이 유지/활성 필터 통일 (2026-09-03, 697fb75)
- [x] 자동 제외(410/404) 모델 정리 상태 표시 (2026-09-03, e6ea29c)
- [x] 오류 안내 메시지 상태코드별 명확화 (2026-09-03, a3e8173)
- [x] T-202 topP/maxTokens 파라미터 — 인프라+편집 UI+tok/s 메트릭 (2026-09-03, e2530f5·fad17a7)
- [x] T-203 평가(Eval) 그리드 — 프롬프트×모델 매트릭스·5개 병렬·점수·회귀·내보내기 (2026-09-03)
- [x] T-206 비교 자동 판정·합성·Diff — 판정 모델 공급자 우선·합성 답변·라인 Diff 뷰어 (2026-09-03)
