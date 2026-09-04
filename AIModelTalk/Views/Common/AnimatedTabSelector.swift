import SwiftUI

// MARK: - AnimatedTabSelector (Osaurus 스타일 애니메이션 탭 셀렉터)

/// 설정창 등에서 사용하는 애니메이션 탭 전환 컴포넌트
/// 선택된 탭에 따라 인디케이터가 부드럽게 이동
/// Osaurus의 Common.AnimatedTabSelector 참고
struct AnimatedTabSelector<T: Hashable>: View {
    @Environment(\.theme) private var theme
    @Binding var selection: T
    let tabs: [TabItem<T>]
    var height: CGFloat = 36

    struct TabItem<T: Hashable>: Identifiable {
        let id: T
        let label: String
        let icon: String?
    }

    @State private var indicatorFrame: CGRect = .zero
    @State private var containerFrame: CGRect = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 배경
                RoundedRectangle(cornerRadius: theme.inputCornerRadius, style: .continuous)
                    .fill(theme.secondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.inputCornerRadius, style: .continuous)
                            .stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: theme.defaultBorderWidth)
                    )

                // 이동하는 인디케이터
                if let selectedTab = tabs.first(where: { $0.id == selection }),
                   let index = tabs.firstIndex(where: { $0.id == selection }) {
                    let tabWidth = geo.size.width / CGFloat(tabs.count)
                    let xOffset = tabWidth * CGFloat(index)

                    RoundedRectangle(cornerRadius: theme.inputCornerRadius - 2, style: .continuous)
                        .fill(theme.accentColor)
                        .frame(width: tabWidth - 4, height: height - 4)
                        .offset(x: xOffset + 2)
                        .animation(theme.springAnimation, value: selection)
                        .shadow(
                            color: theme.shadowColor.opacity(theme.shadowOpacity),
                            radius: 4, y: 1
                        )
                }

                // 탭 버튼들
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        Button(action: {
                            withAnimation(theme.springAnimation) {
                                selection = tab.id
                            }
                        }) {
                            HStack(spacing: 6) {
                                if let icon = tab.icon {
                                    Image(systemName: icon)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                Text(tab.label)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(selection == tab.id ? .white : theme.secondaryText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: height)
            .onAppear {
                containerFrame = geo.frame(in: .local)
            }
        }
        .frame(height: height)
    }
}

// MARK: - SegmentedPickerStyle Alternative (시스템 스타일 대안)

/// 시스템 스타일 세그먼트 피커 (애니메이션 없음, 네이티브)
struct SegmentedTabPicker<T: Hashable>: View {
    @Binding var selection: T
    let tabs: [(T, String, String?)] // (id, label, icon)

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(tabs, id: \.0) { tab in
                Label(tab.1, systemImage: tab.2 ?? "")
                    .tag(tab.0)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - Preview

#Preview("AnimatedTabSelector") {
    struct PreviewWrapper: View {
        @State var selection = "general"
        let tabs: [AnimatedTabSelector<String>.TabItem] = [
            AnimatedTabSelector.TabItem(id: "general", label: "일반", icon: "gear"),
            AnimatedTabSelector.TabItem(id: "providers", label: "공급자", icon: "key"),
            AnimatedTabSelector.TabItem(id: "models", label: "모델", icon: "cpu"),
            AnimatedTabSelector.TabItem(id: "mcp", label: "MCP", icon: "externaldrive"),
        ]

        var body: some View {
            AnimatedTabSelector(selection: $selection, tabs: tabs)
                .frame(width: 500)
                .padding()
                .environment(\.theme, ThemeBox(LightTheme()))
        }
    }

    return PreviewWrapper()
}