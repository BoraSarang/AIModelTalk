# PLAN v0.2.5 — Osaurus 스타일 테마 인프라 & 컴포넌트 라이브러리

> **작성일**: 2026-09-04  
> **플랫폼**: macOS (SwiftUI, macOS 15.5+ / 26 Liquid Glass)  
> **목표**: AIModelTalk에 Osaurus급 네이티브 macOS 디자인 시스템 적용 — 테마 인프라 구축 + 공통 컴포넌트 라이브러리 완성

---

## 1. 배경 및 목적

### 1.1 현황
- 현재 `DesignSystem.swift` 단일 `enum DS`로 기본 토큰만 관리
- 라이트/다크 대응 미흡, 커스텀 테마 불가
- 컴포넌트 라이브러리 부재 → 버튼/시트/다이얼로그/카드 각자 구현
- 글라스(Liquid Glass) 미지원, 마스코트 캐릭터 없음

### 1.2 목표 (Osaurus 벤치마크)
| 영역 | Osaurus 수준 | 현재 | 목표 |
|------|-------------|------|------|
| 테마 시스템 | Light/Dark/Custom + Agent별 | 단일 DS | 완전 구축 |
| 색상 토큰 | 50+ 시맨틱 + WCAG AA | ~10개 | 50+ 토큰 |
| 글라스 | macOS 26 네이티브 + 폴백 | `.regularMaterial`만 | 완전 지원 |
| 컴포넌트 | 20+ 통일 라이브러리 | `dsCard/dsDot/dsBadge`만 | 20+ 컴포넌트 |
| 애니메이션 | Spring(0.35/0.85) 통일 | easeInOut | Spring 통일 |
| 마스코트 | 공룡 캐릭터 전체 UX | 없음 | 캐릭터 적용 |

---

## 2. 확정 설계 결정

| # | 항목 | 결정 | 비고 |
|---|------|------|------|
| 1 | Splash 하이라이터 | **SPM** 추가 | `https://github.com/JohnSundell/Splash` |
| 2 | 캐릭터 일러스트 | **사용자 제작** | 프롬프트 제공 → AI 생성 → PDF 벡터 → Assets |
| 3 | DS 마이그레이션 | **호환 레이어 유지** | Phase 3에서 완전 제거 |
| 4 | 설정창 탭 높이 | **고정 `minHeight: 520`** | 윈도우 크기 점프 방지 |
| 5 | 에이전트/테마 | Phase 1-2: 세션 기반 → Phase 3: `ChatSession.themeID?` | 점진적 도입 |

---

## 3. 구현 범위

### Phase 1: 테마 인프라 (5-7일)
```
Core/
├── Theme.swift                      # ThemeProtocol + LightTheme/DarkTheme + EnvironmentKey
├── ThemeManager.swift               # @Observable 싱글톤, 시스템 외형/액센트 추적
├── CustomTheme.swift                # 사용자 커스텀 테마 모델 (JSON 직렬화)
├── ThemeConfigurationStore.swift    # UserDefaults 저장소
├── DesignSystem.swift               # DS → ThemeProtocol 기본 구현 흡수 (호환 레이어)
```

### Phase 2: 공통 컴포넌트 라이브러리 (5-7일)
```
Views/Common/
├── MinimalCard.swift                # 카드 배경 + 호버/프레스 scale/shadow
├── SimpleCard.swift                 # 콘텐츠 래퍼 (padding + MinimalCard)
├── GradientButton.swift             # Primary/Secondary/Destructive + 로딩
├── SimpleToggleButton.swift         # 토글 (연결/해제, 활성/비활성)
├── FittedSheetFrame.swift           # 540×620 표준, 비대칭 spring 트랜지션
├── ThemedAlertDialog.swift          # 테마 적용 알림 (contained/wide)
├── ThemedBackgroundLayer.swift      # 솔리드/그라디언트/이미지 + 오버레이
├── GlassBackground.swift            # macOS 26 글라스 + 폴백 래퍼
├── GlassListRow.swift               # 리스트 행 글라스 배경 + 선택/호버
├── SearchField.swift                # 툴바/전역 검색 (Cmd-F 포커스)
├── AnimatedTabSelector.swift        # 설정 탭 전환 spring 애니메이션
├── SectionHeader.swift              # ALL CAPS + tracking 1.4
├── AuthModeBadge.swift              # 인증 방식 뱃지 (공통화)
├── ProviderCard.swift               # MCP 공급자 카드 (그리드용)
├── ProviderRowCard.swift            # 공급자 행 카드 (리스트용)
├── AvatarView.swift                 # 이니셜/이미지/캐릭터 아바타
├── AgentBadge.swift                 # 공급자·모델 배지
├── CodeBlockView.swift              # Splash 하이라이트 + 복사 버튼
├── FloatingInputCard.swift          # 글라스 + 그라데이션 크롬 입력바
├── EmptyStateView.swift             # 캐릭터 일러스트 + 액션
├── ToastManager.swift               # 토스트 (성공/경고/에러 + 캐릭터)
└── CharacterIllustrations.swift     # 마스코트 에셋 상수 관리
```

---

## 4. 핵심 기술 스펙

### 4.1 ThemeProtocol 주요 토큰 (50+)
```swift
protocol ThemeProtocol {
    // 색상 (시맨틱)
    var primaryText: Color { get }
    var secondaryText: Color { get }
    var primaryBackground: Color { get }
    var cardBackground: Color { get }
    var cardBorder: Color { get }
    var accentColor: Color { get }
    var primaryBorder: Color { get }
    var focusBorder: Color { get }
    var successColor: Color { get }
    var warningColor: Color { get }
    var errorColor: Color { get }
    // 글라스 (macOS 26+)
    var glassEnabled: Bool { get }
    var glassOpacityPrimary: Double { get }
    var glassBlurRadius: Double { get }
    var glassMaterial: NSVisualEffectView.Material { get }
    // 그림자/고도
    var shadowColor: Color { get }
    var shadowOpacity: Double { get }
    var cardShadowRadius: Double { get }
    var cardShadowRadiusHover: Double { get }
    // 타이포그래피
    var primaryFontName: String { get }
    var monoFontName: String { get }
    var bodySize: Double { get }
    var codeSize: Double { get }
    func font(size: CGFloat, weight: Font.Weight) -> Font
    func monoFont(size: CGFloat, weight: Font.Weight) -> Font
    // 애니메이션
    var animationSpringResponse: Double { get }
    var animationSpringDamping: Double { get }
    func springAnimation() -> Animation
    // 코너/보더
    var cardCornerRadius: Double { get }
    var inputCornerRadius: Double { get }
    var defaultBorderWidth: Double { get }
    // 말풍선 커스터마이징
    var bubbleCornerRadius: Double { get }
    var userBubbleOpacity: Double { get }
    var assistantBubbleOpacity: Double { get }
    var showEdgeLight: Bool { get }
    var showInlineAvatar: Bool { get }
}
```

### 4.2 Light/Dark 테마 색상 (WCAG AA 준수)
| 토큰 | Light (Warm) | Dark (Cool) |
|------|--------------|-------------|
| `primaryText` | `#1a1a18` (17:1) | `#f5f5f0` (17:1) |
| `secondaryText` | `#555550` (7:1) | `#b8b8b0` (7:1) |
| `primaryBackground` | `#ffffff` | `#181816` |
| `cardBackground` | `#ffffff` | `#1e1e1c` |
| `cardBorder` | `#d0d0cc` | `#3a3a36` |
| `accentColor` | `#1a1a18` | `#f5f5f0` |
| `inputBorder` | `#a8a8a3` | `#4a4a46` |
| `glassOpacityPrimary` | 0.25 | 0.35 |

### 4.3 표준 시트/트랜지션
```swift
// FittedSheetFrame: 540×620 고정
// Transition: 비대칭 spring
.asymmetric(
    insertion: .opacity.combined(with: .offset(x: 30)).combined(with: .scale(0.98)),
    removal: .opacity.combined(with: .offset(x: -30)).combined(with: .scale(0.98))
)
// Animation: .spring(response: 0.35, dampingFraction: 0.85)
```

### 4.4 캐릭터 에셋 목록
| 에셋명 | 용도 | 크기 | 포맷 |
|--------|------|------|------|
| `character-wave` | 온보딩 환영 | 400×400 | PDF 벡터 |
| `character-empty` | 빈 상태 | 200×200 | PDF 벡터 |
| `character-thinking` | 스트리밍 중 | 120×120 | PDF 벡터 (3프레임) |
| `character-success` | 성공 토스트 | 120×120 | PDF 벡터 |
| `character-error` | 에러 토스트 | 120×120 | PDF 벡터 |
| `character-small` | 사이드바 장식 | 64×64 | PDF 벡터 |

---

## 5. 구현 순서 (일자별)

| 일차 | 작업 | 산출물 | 검증 |
|------|------|--------|------|
| Day 1-2 | Theme.swift + ThemeManager + CustomTheme | 테마 프로토콜/매니저/모델 | 라이트/다크 전환 테스트 |
| Day 3 | DesignSystem.swift 마이그레이션 | 호환 레이어 완성 | 기존 뷰 컴파일 에러 0 |
| Day 4 | ThemeConfigurationStore + App 주입 | Environment 전파 | `@Environment(\.theme)` 동작 |
| Day 5-6 | 컴포넌트 그룹 A/B 병렬 | 버튼/카드/시트/배경/다이얼로그 | 프리뷰 테스트 |
| Day 7 | 글라스/검색/탭 셀렉터 | GlassBackground, SearchField, AnimatedTabSelector | macOS 26 글라스 + 폴백 |
| Day 8 | 설정창용 컴포넌트 | SectionHeader, AuthModeBadge, ProviderCard | MCPSettingsView 적용 준비 |
| Day 9 | 채팅용 컴포넌트 | AvatarView, AgentBadge, CodeBlockView(Splash), FloatingInputCard | 하이라이트/입력바 테스트 |
| Day 10 | 빈상태/토스트/캐릭터 | EmptyStateView, ToastManager, CharacterIllustrations | 캐릭터 에셋 Assets 추가 |
| Day 11 | 통합 테스트 | 전체 빌드/실행 | `build_and_run.sh debug macos` 통과 |

---

## 6. 완료 기준 (DoD)

| 검증 항목 | 통과 기준 |
|----------|----------|
| **테마 즉시 전환** | 시스템 라이트/다크/커스텀 3종 → 0.3s 애니메이션으로 전체 뷰 반영 |
| **글라스 렌더링** | macOS 26: 사이드바/툴바/시트/팝오버 Liquid Glass / Reduce Transparency: 불투명 폴백 |
| **컴포넌트 통일** | 모든 버튼=GradientButton, 시트=FittedSheetFrame, 다이얼로그=ThemedAlertDialog |
| **마스코트 표시** | 빈 상태/온보딩/스트리밍/토스트에 캐릭터 일러스트 정상 표시 |
| **기능 회귀 없음** | 설정창/채팅창/사이드바/디버그 패널/비교 오버레이 정상 동작 |
| **빌드 성공** | `xcodebuild` + `./build_and_run.sh debug macos` 무오류 통과 |
| **SPLASH 연동** | 코드 블록에서 Swift/JSON/Markdown 하이라이트 + 복사 버튼 동작 |

---

## 7. Phase 3 연계 (예고)

Phase 1-2 완료 후 즉시 진행:
1. `SettingsView` → `.formStyle(.grouped)` + `AnimatedTabSelector` + `minHeight: 520`
2. `MCPSettingsView` → `ProviderCard` 그리드 + 헬스 스냅샷 카드
3. `ProvidersSettingsView` → `RemoteProviderEditSheet` 스타일 스텝드 플로우
4. `ChatSession.themeID?: String` 추가 → 세션별 테마 지원

---

## 8. 위험 요소 및 완화

| 위험 | 영향도 | 완화 방안 |
|------|--------|----------|
| 테마 마이그레이션 중 컴파일 에러 | 높음 | 호환 레이어(`extension ThemeProtocol`)로 기존 `DS.` 코드 무수정 유지 |
| macOS 26 미만 글라스 폴백 실패 | 중간 | `#available(macOS 26, *)` 가드 + `.regularMaterial` 폴백 패턴 필수 적용 |
| Splash 빌드 이슈 | 낮음 | SPM 추가 후 `xcodebuild -resolvePackageDependencies` 선실행 |
| 캐릭터 에셋 제작 지연 | 중간 | 플레이스홀더 SF Symbol로 대체 후 추후 교체 가능 |
| 기존 설정창 레이아웃 깨짐 | 중간 | `.formStyle(.grouped)` + 고정 높이로 단계적 적용 |

---

## 9. 승인 및 시작

- [ ] 계획 문서 검토 완료
- [ ] 캐릭터 일러스트 제작 착수 (병렬)
- [ ] Phase 1 구현 시작

**승인자**: _______________  
**날짜**: _______________