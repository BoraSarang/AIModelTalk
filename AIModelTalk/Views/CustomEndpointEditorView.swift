import SwiftUI

/// 커스텀 엔드포인트 생성/편집 시트 — v1.9 T-84
/// endpoint가 nil이면 신규 생성. 연결 테스트를 내장한다.
struct CustomEndpointEditorView: View {
    let endpoint: CustomEndpoint?
    let onSave: (CustomEndpoint) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var testResult: String?

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var draftEndpoint: CustomEndpoint {
        var result = endpoint ?? CustomEndpoint(name: "")
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.baseURL = normalizeURL(baseURL)
        result.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(endpoint == nil ? "엔드포인트 추가" : "엔드포인트 편집")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Form {
                TextField("이름 (예: LM Studio, OpenAI)", text: $name)

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Base URL (예: http://localhost:1234/v1)", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { baseURL = normalizeURL(baseURL) }
                    Text("OpenAI 호환 엔드포인트를 /v1까지 포함해 입력하세요. 클라이언트가 /chat/completions를 붙입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SecureField("API 키 (로컬 서버는 비워도 됨)", text: $apiKey)

                HStack {
                    Button {
                        runTest()
                    } label: {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("연결 테스트")
                        }
                    }
                    .disabled(isTesting || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                    }
                    Spacer()
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(endpoint == nil ? "추가" : "저장") {
                    onSave(draftEndpoint)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(16)
        }
        .onAppear(perform: loadInitialValues)
    }

    /// 스킴 자동 보정(localhost http / 나머지 https) + 슬래시 제거
    private func normalizeURL(_ value: String) -> String {
        var url = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return url }
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            let isLocal = url.hasPrefix("localhost") || url.hasPrefix("127.0.0.1")
            url = (isLocal ? "http://" : "https://") + url
        }
        while url.hasSuffix("/") { url = String(url.dropLast()) }
        return url
    }

    private func loadInitialValues() {
        guard let source = endpoint else { return }
        name = source.name
        baseURL = source.baseURL
        apiKey = source.apiKey
    }

    /// 저장 전 현재 입력값으로 즉시 테스트
    private func runTest() {
        isTesting = true
        testResult = nil
        Task {
            let result = await CustomEndpoint.testConnection(draftEndpoint)
            await MainActor.run {
                testResult = result
                isTesting = false
            }
        }
    }
}
