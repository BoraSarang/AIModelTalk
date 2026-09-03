import SwiftUI

/// Ollama 모델 관리 뷰 — 설치/삭제/진행률 (v1.8 T-70d)
struct ModelManagerView: View {
    @ObservedObject private var ollamaService = OllamaService.shared
    @ObservedObject private var catalog = ModelCatalog.shared
    @State private var newModelName = ""
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var installedModels: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 헤더
            HStack {
                dsDot(Color.teal, size: DS.dotLarge)
                Text("Ollama 모델 관리")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await loadInstalledModels() }
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }

            Divider()

            // 설치된 모델 목록
            if installedModels.isEmpty && !isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    Text("설치된 모델이 없습니다")
                        .foregroundStyle(.secondary)
                    Text("아래에서 모델을 설치하거나, Ollama 서버가 실행 중인지 확인하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(DS.windowInset)
            } else {
                List {
                    ForEach(installedModels, id: \.self) { modelName in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(modelName)
                                    .font(.callout)
                                if let progress = ollamaService.pullProgress[modelName],
                                   progress < 1.0 {
                                    ProgressView(value: progress)
                                        .controlSize(.small)
                                    Text("설치 중… \(Int(progress * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await deleteModel(modelName) }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .disabled(ollamaService.isPulling)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Divider()

            // 모델 설치
            VStack(alignment: .leading, spacing: 10) {
                Text("모델 설치")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    TextField("모델 이름 (예: llama3.2, gemma2:2b, qwen2.5:7b)", text: $newModelName)
                        .textFieldStyle(.roundedBorder)
                    Button("설치") {
                        Task { await installModel(newModelName) }
                    }
                    .disabled(newModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ollamaService.isPulling)
                }

                if let error = loadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // 추천 모델 퀵 버튼
                VStack(alignment: .leading, spacing: 6) {
                    Text("추천 무료 모델")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recommendedModels, id: \.self) { model in
                                Button(model) {
                                    newModelName = model
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            if let error = ollamaService.pullError {
                Text("오류: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(DS.windowInset)
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            Task { await loadInstalledModels() }
        }
    }

    var recommendedModels: [String] {
        ["llama3.2", "llama3.2:1b", "gemma2:2b", "gemma2:9b", "qwen2.5:7b", "qwen2.5:14b", "phi3.5", "mistral:7b", "codellama:7b", "deepseek-coder:6.7b"]
    }

    func loadInstalledModels() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let baseURL = AppSettings.shared.ollamaBaseURL.isEmpty ? Provider.ollama.baseURL : AppSettings.shared.ollamaBaseURL
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            loadError = "Ollama 서버 URL이 설정되지 않았습니다. 설정 → 공급자에서 확인하세요."
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["models"] as? [[String: Any]] else {
                loadError = "응답 파싱 실패"
                return
            }
            installedModels = list.compactMap { $0["name"] as? String }.sorted()
        } catch {
            loadError = "서버 연결 실패: \(error.localizedDescription) — Ollama가 실행 중인지 확인하세요 (ollama serve)."
        }
    }

    func installModel(_ name: String) async {
        loadError = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await ollamaService.pullModel(trimmed)
            await loadInstalledModels()
            Task { await catalog.refresh() }
        } catch {
            loadError = "설치 실패: \(error.localizedDescription)"
        }
    }

    func deleteModel(_ name: String) async {
        do {
            try await ollamaService.deleteModel(name)
            await loadInstalledModels()
        } catch {
            loadError = "삭제 실패: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ModelManagerView()
}