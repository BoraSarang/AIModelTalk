import SwiftUI

/// 첫 실행 온보딩 — macOS 네이티브 웰컴 스타일 3슬라이드 (v2.0 T-83, 디자인 개편 v2.1 T-101)
/// 앱아이콘 타일 + 워드마크 + 아이콘 피처 행 구성. 슬라이드 메타는 테스트 검증 대상.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    /// 피처 행 — 아이콘 + 제목 + 상세
    struct Feature {
        let icon: String
        let title: String
        let detail: String
    }

    struct Slide {
        let icon: String
        let title: String
        let subtitle: String
        let features: [Feature]
    }

    /// 슬라이드 메타 — 테스트 검증 대상
    static let slides: [Slide] = [
        Slide(
            icon: "bubble.left.and.text.bubble.right",
            title: "AI Model Talk",
            subtitle: "AI 모델 톡 — 여러 AI를 하나의 채팅에서",
            features: [
                Feature(icon: "cpu", title: "다양한 공급자",
                        detail: "NVIDIA · OpenRouter · Groq · Gemini 무료 모델과 Ollama · Apple Intelligence까지"),
                Feature(icon: "folder", title: "대화 관리",
                        detail: "프로젝트 폴더와 대화 분기, 전역 검색으로 흐름을 정리합니다"),
                Feature(icon: "bolt.fill", title: "어디서든 빠르게",
                        detail: "⌥ Space 빠른 대화 패널과 ⌘ F 전역 검색을 지원합니다"),
            ]
        ),
        Slide(
            icon: "cpu",
            title: "공급자 연결하기",
            subtitle: "설정 → 공급자에서 시작하세요",
            features: [
                Feature(icon: "apple.logo", title: "Apple Intelligence",
                        detail: "별도 설정 없이 즉시 사용 가능 (macOS 26 이상)"),
                Feature(icon: "server.rack", title: "Ollama · LM Studio",
                        detail: "로컬 서버 주소만 입력하거나 OpenAI 호환 엔드포인트로 연결"),
                Feature(icon: "key.fill", title: "API 키",
                        detail: "NVIDIA · OpenRouter · Groq · Gemini · OpenAI · Anthropic 중 선택"),
            ]
        ),
        Slide(
            icon: "keyboard",
            title: "단축키 익히기",
            subtitle: "자주 쓰는 세 가지만 기억하세요",
            features: [
                Feature(icon: "command", title: "⌥ Space",
                        detail: "어디서든 빠른 대화 패널 열기"),
                Feature(icon: "magnifyingglass", title: "⌘ F",
                        detail: "모든 대화 메시지 전역 검색"),
                Feature(icon: "doc.on.clipboard", title: "⌘ I",
                        detail: "선택한 텍스트 가져오기 (접근성 권한 필요)"),
            ]
        ),
    ]

    /// 타일 그라디언트 — 슬라이드별 브랜드 컬러
    private var tileGradient: LinearGradient {
        let colors: [[Color]] = [
            [Color(hex: "#0A84FF") ?? .blue, Color(hex: "#BF5AF2") ?? .purple],
            [Color(hex: "#30D158") ?? .green, Color(hex: "#64D2FF") ?? .cyan],
            [Color(hex: "#FF9F0A") ?? .orange, Color(hex: "#FF375F") ?? .pink],
        ]
        return LinearGradient(colors: colors[page], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Self.slides.indices, id: \.self) { index in
                    slide(index)
                        .tag(index)
                }
            }

            // 페이지 인디케이터 — macOS에 .page 스타일 미지원 → 수동 도트
            HStack(spacing: 8) {
                ForEach(Self.slides.indices, id: \.self) { i in
                    dsDot(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                }
            }
            .padding(.bottom, 14)

            HStack {
                Button("이전") {
                    page = max(0, page - 1)
                }
                .disabled(page == 0)

                Spacer()

                if page < Self.slides.count - 1 {
                    Button("다음") {
                        page = min(Self.slides.count - 1, page + 1)
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("시작하기") {
                        complete()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, DS.windowInset)
            .padding(.bottom, DS.windowInset)
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear {
            DebugLogger.shared.info("APP", "[FEATURE] 온보딩 표시됨")
        }
    }

    // MARK: - 슬라이드

    @ViewBuilder
    private func slide(_ index: Int) -> some View {
        let meta = Self.slides[index]

        VStack(spacing: 22) {
            Spacer()

            // 앱아이콘 타일 — 그라디언트 라운드 사각 + 흰색 심볼
            ZStack {
                RoundedRectangle(cornerRadius: DS.radiusPanel)
                    .fill(page == index ? AnyShapeStyle(tileGradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                Image(systemName: meta.icon)
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 84, height: 84)
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)

            VStack(spacing: 6) {
                Text(meta.title)
                    .font(.system(size: 26, weight: .bold))
                Text(meta.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            // 피처 행 — 좌측정렬 아이콘 리스트
            VStack(spacing: 14) {
                ForEach(meta.features.indices, id: \.self) { i in
                    featureRow(meta.features[i])
                }
            }
            .padding(.horizontal, 44)

            Spacer()
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.radiusControl))

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        DebugLogger.shared.info("APP", "[FEATURE] 온보딩 완료 처리됨")
        dismiss()
    }
}
