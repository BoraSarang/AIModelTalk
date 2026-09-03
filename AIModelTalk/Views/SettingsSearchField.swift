import SwiftUI

// MARK: - 설정 화면 공용 검색 필드 (v3.2 T-149)
// 모델/스킬 탭에서 동일한 검색 UI를 보장하기 위한 공통 컴포넌트.
// magnifyingglass + 플레이스홀더 + 클리어 버튼, quaternaryLabelColor 라운드 박스.
// 가로 여백은 호출부(Form Section / split 콘텐츠)가 제어한다 (v3.2 T-156).

struct SettingsSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .quaternaryLabelColor))
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusControl))
    }
}
