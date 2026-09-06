# TODO — AIModelTalk v0.3.4 (진행 중)

- [x] T-342 wigolo 기본 내장 MCP — presets 1줄 + 기본 시드(enabled) + npx 탐색기 + E-MAC-MCP-1001 (PLAN: `docs/plans/PLAN-macos-T342.md`, 2026-09-06)
- [x] T-343 퀵챗 테마 미적용 — 별도 NSPanel 호스팅에 themeEnvironment 미주입 → 2곳에 추가 (2026-09-06)
- [ ] T-344 README·랜딩·릴리즈·Pages·Actions — README 확장 + site/ 랜딩 + ci/pages/release 워크플로 + v0.1.0 릴리즈 (PLAN: `docs/plans/PLAN-macos-T344.md`)

# TODO — AIModelTalk v0.3.3

- [x] T-337 Follow up 후속질문 — LLM 생성 3개 + 말풍선 섹션 + 클릭 즉시 전송 (2026-09-05)
- [x] T-338 질문 목차 — 툴바 버튼 + 팝오버 + 기존 점프 인프라로 이동 (2026-09-05)
- [x] T-337b Follow up 우측 인덴트 — 응답 하단 우측 블록 (Spacer 구조) (2026-09-05)
- [x] T-337c Follow up 아랫줄 이동 — 푸터 HStack 밖 VStack 직속 (뭉침 해소) (2026-09-06)
- [x] T-337d Follow up 한글화 — 헤더 "후속 질문" + 프롬프트 한국어 강화 (2026-09-06)
- [x] T-339 메시지 되돌리기 — 선택 메시지 포함 절단 + 입력창 프리필(전송 없음) + 자동 기억 회수 (2026-09-06)
- [x] T-340 사용자 말풍선 2줄 — 1행 대화 / 2행 시간·분기·되돌리기 (2026-09-06)
- [x] T-341 세션 증발 수정 — 저장소 전용 경로 분리 + 세션 로드/저장 실패 로그 + 모드·모델 영속 보장 (2026-09-06)

- [x] T-334 코딩 모델 선택 미반영 수정 — send() 코딩 분기 (선택 모델로 전송) (2026-09-05)
- [x] T-335 토큰 팝오버 앵커를 배지 버튼으로 이동 (본체 VStack → 배지) (2026-09-05)
- [x] T-336 주 라인 배지 통일 — 첨부·웹·더보기 pill + hover (A안) (2026-09-05)

- [x] T-331 검증된 무료 모델 카탈로그 반영 — Zen/OpenRouter/NIM 대조(2026-09-05 기준) 후 defaultModels·fallbackPriority·codingPreferredIDs·supportsVision 갱신 (무료만) (2026-09-05)
- [x] T-332 오디오 모드 추가 + 모드별 추천 일원화 + 추천 기본 활성화 — ChatMode.audio·AudioClient(NIM /audio/speech)·sendAudio·말풍선 재생·defaultEnabledIDs (2026-09-05)
- [x] T-333 전체 MCP 공급자 자동/수동 OAuth 병행 — 모드 선택 UI + 커스텀 엔드포인트 + 갱신 경로 반영 (T-328 흡수) (2026-09-05)

# TODO — AIModelTalk v0.3.2

v0.3.2 "토큰 상태 표시" (v0.2.6~0.3.1 완료). 상세: `docs/plans/PLAN_v0.3.2_macos.md`.
범위 확정: 축2 비용(USD) 제거 / 채팅 하단 토큰 상태 배지·팝오버 / 설정 토큰 상태 탭(사용 중 공급자·모델만).

## 완료 (v0.3.2)

- [x] T-321 비용 제거 — ChatMessage.costUSD·SessionCost·AIModel 가격필드(isPaid)·ModelsSettings 가격 편집 UI·말풍선 실비용·CostSettingsView 삭제 (2026-09-05)
- [x] T-322 토큰 배지 — TokenQuota.swift 스냅샷(실측 누적+추정 폴백)/계정풀(Anthropic 헤더) + ChatInputBarView "남음 N 토큰" 배지·팝오버 (2026-09-05)
- [x] T-323 토큰 상태 탭 — 활성 공급자·모델(실측 사용 기록만) 테이블, 설정 탭명 "토큰 상태"·아이콘 tuningfork (2026-09-05)
- [x] T-324 GradientButton 다크 복구 — 배경 luminance 반전이 글자색/스피너 tint (AllPrimary 버튼 전역) (2026-09-05)
- [x] T-325 MCP 헬스바 → 섹션 헤더 병합 — 공급자 요약을 헤더줄 소형 표시 + ProviderCard 레이아웃(overlay→background) 수정 (2026-09-05)
- [x] T-326 MCP 공급자 중복 방지 — connectOAuth에서 동일 templateID+정규화 url 기존 항목 id 재사용 + 삭제 컨펌(단일 alert) + 빈 상태 compact (2026-09-05)
- [x] T-327 수동 OAuth 연결 — Linear/GitHub를 .oauth21Manual 전환 + Client ID/Secret 입력 폼 + 고정 루프백 포트(13000) 리다이렉트 URI 안내 + 수동 엔드포인트 경로 (2026-09-05)
- [x] T-329a: 용도 모드 세그먼트 동작 복구 — setMode에서 _cachedSession 무효화 누락으로 Picker/이미지 전송 분기가 stale 상태 읽던 버그 수정 + 세션 영속화 (2026-09-05)
- [x] T-329b: 이미지/코딩 모델 선택 — ChatSession.selectedImageModelID·selectedCodingModelID(provider:id) + ChatViewModel 선택/해제 헬퍼 + 이미지 전송이 선택 모델 사용 (2026-09-05)
- [x] T-329c: 입력바 모드 컨트롤 줄 — 이미지=생성 모델 메뉴(gpt-image-1/dall-e-3), 코딩=추천 세트∩활성 모델 메뉴 + 워크스페이스 폴더 선택/변경/해제(NSOpenPanel) (2026-09-05)
- [x] T-329d: 코딩 파일 목록 접이식 패널 — 상위 3레벨 트리(디렉터리 우선) + 컨텍스트 메뉴(경로 복사/입력창 삽입) (2026-09-05) — 실기동 확인 대기
- [x] T-329e: 코딩 모델 Menu가 한글 입력 IME 교착(IMK→TSM XPC 응답 유실, 메인 스레드 HIRunLoopSemaphore 스핀 CPU 105%) 유발 → 이미지/코딩 모델 선택을 **Menu → 팝오버 목록**으로 교체 + 세그먼트 좌측 정렬 고정 (2026-09-05)

## 백로그

- [x] T-328 GitLab·Notion·Slack 등 수동 지원 — T-333에 흡수 (전 공급자 자동/수동 병행, 2026-09-05)
- [x] T-320 코드 블록 Splash SPM 연동 — Splash 0.16.0 해결·Swift만 Splash(타언어 regex 유지)·AppSplashTheme 매핑 (2026-09-05)
- [ ] T-* 크레딧 충전/잔액 백엔드 연동 (백엔드 준비 시)

## 완료 (v0.3.1)

- [x] 축4a: 용도 모드 분리(채팅/이미지/코딩) — ChatSession.mode + 입력바 세그먼트 (2026-09-05, 3d539a0)
- [x] 축4b: DALL-E/이미지 생성 — ImageClient + imageModels(gpt-image-1/dall-e-3) + sendImage + 어시스턴트 말풍선 표시·저장 (2026-09-05, 3d539a0)
- [x] 기동 크래시 수정 — ThemeManager 시작 시 NSApp nil 강제언랩 → optional 안전화 (2026-09-05)

## 완료 (v0.3.0)

- [x] 축3a: workspaceFolder 지정(NSOpenPanel) + 시스템 프롬프트 주입 (2026-09-05, 3b601f8)
- [x] 축3b: FileSystemTools(list_dir/read_file/write_file/edit_file) + 경로 샌드박스 + 권한 게이트 (2026-09-05, 3b601f8)

## 완료 (v0.2.7)

- [x] 축2: AIModel 가격 필드 + ModelCatalog 유료 모델 가격 + SessionCost 계산($0.00 제거) + CostSettingsView/비용 탭 (2026-09-05, e4d532f)

## 완료 (v0.2.6)

- [x] 축1a: ThemeManager + 앱 루트 테마 주입 + 설정 테마 선택 UI (2026-09-05, 711d021)
- [x] 축1b: 16개 뷰 테마/글라스 적용 + DS.* 전면 제거 0건 (2026-09-05, 711d021)

## 완료 (v0.2.5까지)

- [x] v0.2.5 Osaurus 테마 인프라 + 컴포넌트 22개 + Phase 3-1~4 일부 적용 (2026-09-05)

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
