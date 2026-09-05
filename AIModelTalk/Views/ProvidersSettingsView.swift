import SwiftUI

struct ProvidersSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.theme) private var theme
    @State private var ollamaBaseURL: String = ""
    @State private var ollamaIsTesting = false
    @State private var ollamaTestResult: String?
    /// 커스텀(OpenAI 호환) 다중 엔드포인트 — v1.9 T-84
    @State private var customEndpoints: [CustomEndpoint] = []
    @State private var customTestResults: [UUID: String] = [:]
    @State private var customTestingIDs: Set<UUID> = []
    @State private var editingEndpoint: CustomEndpoint?
    @State private var showCustomEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space12) {
                ThemedSettingsCard("모델 공급자") {
                    HStack(spacing: theme.space10) {
                        Circle()
                            .fill(Color.indigo)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Intelligence")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(theme.primaryText)
                            ThemedSettingsCaption("macOS 26+ 내장")
                        }
                        Spacer()
                        if #available(macOS 26.0, *) {
                            Text("사용 가능")
                                .font(.caption)
                                .foregroundStyle(theme.successColor)
                        } else {
                            ThemedSettingsCaption("macOS 26 필요")
                        }
                    }
                }

                ThemedSettingsCard("Ollama (로컬, 설치 필요)") { ollamaSection }

                ThemedSettingsCard("커스텀 (OpenAI 호환)") { customSection }

                ThemedSettingsCard("API 키 필요 공급자") {
                    ForEach(Provider.allCases.filter { $0.requiresAPIKey && $0 != .custom }) { provider in
                        ProviderRow(provider: provider)
                    }
                }
            }
            .padding(theme.space16)
        }
    }

    private var ollamaSection: some View {
        VStack(alignment: .leading, spacing: theme.space10) {
            TextField("서버 URL (예: http://localhost:11434)", text: $ollamaBaseURL)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    ollamaBaseURL = settings.ollamaBaseURL
                }
            HStack {
                ThemedSettingsCaption("로컬 Ollama 서버가 실행 중이어야 합니다. (ollama serve)")
                Spacer()
                if ollamaIsTesting {
                    ProgressView().controlSize(.small)
                } else if let result = ollamaTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? theme.successColor : theme.errorColor)
                }
                Button("연결 테스트") {
                    Task { await testOllama() }
                }
                .disabled(ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ollamaIsTesting)
            }
        }
        .onChange(of: ollamaBaseURL) { _, newValue in
            var url = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
                url = "http://" + url
            }
            if url.hasSuffix("/") { url = String(url.dropLast()) }
            settings.ollamaBaseURL = url
        }
    }

    @ViewBuilder
    private var customSection: some View {
        VStack(alignment: .leading, spacing: theme.space10) {
            if customEndpoints.isEmpty {
                ThemedSettingsCaption("등록된 엔드포인트가 없습니다. LM Studio, vLLM, OpenAI 공식 API 등을 추가하세요.")
            }
            ForEach(customEndpoints) { endpoint in
                customEndpointRow(endpoint)
            }

            Button {
                editingEndpoint = nil
                showCustomEditor = true
            } label: {
                Label("엔드포인트 추가", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .onAppear { reloadCustomEndpoints() }
        .sheet(isPresented: $showCustomEditor) {
            CustomEndpointEditorView(endpoint: editingEndpoint) { result in
                var store = CustomEndpointStore(defaults: .standard)
                store.upsert(result)
                reloadCustomEndpoints()
                DebugLogger.shared.info("APP", "[FEATURE] 커스텀 엔드포인트 저장 실행됨: '\(result.name)' (\(result.baseURL))")
            }
            .frame(minWidth: 420, minHeight: 380)
        }
    }

    private func reloadCustomEndpoints() {
        customEndpoints = CustomEndpointStore(defaults: .standard).endpoints
    }

    private func deleteCustomEndpoint(_ endpoint: CustomEndpoint) {
        var store = CustomEndpointStore(defaults: .standard)
        store.remove(id: endpoint.id)
        ModelCatalog.shared.clearCustomSyncSnapshot(endpointID: endpoint.id) // 동기화 스냅샷 정리 (v2.1 T-98)
        // 해당 엔드포인트 소속 모델 정리 (복합 ID 프리픽스 일치)
        let prefix = "\(endpoint.id.uuidString):"
        let orphans = ModelCatalog.shared.models.filter {
            $0.provider == .custom && $0.id.hasPrefix(prefix)
        }
        for model in orphans {
            ModelCatalog.shared.removeModel(model)
        }
        reloadCustomEndpoints()
        DebugLogger.shared.info("APP", "[FEATURE] 커스텀 엔드포인트 삭제 실행됨: '\(endpoint.name)', 소속 모델 \(orphans.count)개 정리")
    }

    private func testCustomEndpoint(_ endpoint: CustomEndpoint) async {
        customTestingIDs.insert(endpoint.id)
        defer { customTestingIDs.remove(endpoint.id) }
        customTestResults[endpoint.id] = await CustomEndpoint.testConnection(endpoint)
    }

    /// 엔드포인트 목록 행 — 더블클릭/우클릭 편집, 행별 연결 테스트
    @ViewBuilder
    private func customEndpointRow(_ endpoint: CustomEndpoint) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.name)
                    .fontWeight(.medium)
                Text(endpoint.baseURL.isEmpty ? "URL 미설정" : endpoint.baseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if customTestingIDs.contains(endpoint.id) {
                ProgressView().controlSize(.small)
            } else if let result = customTestResults[endpoint.id] {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.hasPrefix("✓") ? theme.successColor : theme.errorColor)
            }
            Button("테스트") {
                Task { await testCustomEndpoint(endpoint) }
            }
            .disabled(endpoint.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customTestingIDs.contains(endpoint.id))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("편집") {
                editingEndpoint = endpoint
                showCustomEditor = true
            }
            Divider()
            Button("삭제", role: .destructive) {
                deleteCustomEndpoint(endpoint)
            }
        }
        .help("더블클릭: 편집")
        .onTapGesture(count: 2) {
            editingEndpoint = endpoint
            showCustomEditor = true
        }
    }

    private func testOllama() async {
        ollamaIsTesting = true
        ollamaTestResult = nil
        defer { ollamaIsTesting = false }

        var url = ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "http://" + url
        }
        if url.hasSuffix("/") { url = String(url.dropLast()) }

        guard let testURL = URL(string: url + "/api/tags") else {
            ollamaTestResult = "✗ URL 형식 오류"
            return
        }

        var req = URLRequest(url: testURL)
        req.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                ollamaTestResult = "✗ 응답 없음"
                return
            }
            if (200..<300).contains(http.statusCode) {
                let count = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0["models"] as? [[String: Any]] }?.count ?? 0
                ollamaTestResult = "✓ 연결 성공 (모델 \(count)개)"
            } else {
                ollamaTestResult = "✗ HTTP \(http.statusCode)"
            }
        } catch {
            ollamaTestResult = "✗ 연결 실패: \(error.localizedDescription)"
        }
    }
}

struct ProviderRow: View {
    let provider: Provider
    @ObservedObject private var settings = AppSettings.shared
    @State private var key: String = ""
    @State private var saved: Bool = false
    @FocusState private var isFocused: Bool

    private var isConfigured: Bool {
        !settings.apiKey(for: provider).isEmpty
    }

    var body: some View {
        HStack {
            Circle()
                .fill(Color(provider.accentColor))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                HStack {
                    Text(provider.rawValue)
                        .fontWeight(.medium)
                    Text(provider.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isConfigured {
                    Text("저장됨")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            SecureField("API 키", text: $key)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .focused($isFocused)
                .onAppear {
                    key = settings.apiKey(for: provider)
                }
                .onSubmit {
                    save()
                }
                // 포커스 유실 시 자동 저장 — 사용자가 저장 버튼을 누르지 않고
                // 강제 종료돼도 로컬 @State에만 남아 유실되는 문제 방지 (v3.2 T-155)
                .onChange(of: isFocused) { _, focused in
                    if !focused { save() }
                }
                // 입력 즉시 영속 — 키를 타이핑하는 순간마다 setAPIKey→synchronize로
                // 디스크에 기록. 저장 버튼/포커스 유실/강제 종료 타이밍에 무관하게
                // 마지막 입력값이 보존되도록 한다 (v3.2 T-155, 유실 리포트 근본 대응).
                .onChange(of: key) { _, _ in
                    save()
                }

            Button(saveLabel) {
                save()
            }
            .disabled(key.isEmpty)

            if let url = provider.apiKeyURL {
                Link(destination: URL(string: url)!) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .help("API 키 발급 페이지 열기")
            }
        }
        .padding(.vertical, 2)
    }

    private var saveLabel: String {
        if key.isEmpty {
            return "저장"
        } else if saved {
            return "✓ 저장됨"
        }
        return "저장"
    }

    private func save() {
        guard !key.isEmpty else { return }
        settings.setAPIKey(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saved = false
        }
    }
}

#Preview {
    ProvidersSettingsView()
}