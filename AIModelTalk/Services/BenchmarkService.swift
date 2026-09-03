import Foundation

@MainActor
final class BenchmarkService: ObservableObject {
    static let shared = BenchmarkService()

    @Published var isRunning: Bool = false
    @Published var runningModelID: String?

    private let testPrompt = "안녕하세요. 간단히 자기소개를 한 문장으로 해 주세요."

    // MARK: - 단일 모델 벤치마크
    func benchmark(model: AIModel) async -> AIModel? {
        guard let client = try? AIClientFactory.client(provider: model.provider, modelID: model.id) else {
            return nil
        }

        isRunning = true
        runningModelID = model.id
        defer {
            isRunning = false
            runningModelID = nil
        }

        let messages = [ChatMessage(role: .user, content: testPrompt)]
        let start = Date()
        var ttft: TimeInterval?
        var fullText = ""

        do {
            let stream = client.stream(messages: messages, systemPrompt: nil)
            for try await chunk in stream {
                if ttft == nil {
                    ttft = Date().timeIntervalSince(start)
                }
                fullText += chunk
                if fullText.count > 200 { break } // 응답 일부만 받고 종료
            }
        } catch {
            return nil
        }

        guard ttft != nil, !fullText.isEmpty else { return nil }
        let total = Date().timeIntervalSince(start)

        var updated = model
        updated.ttft = ttft
        updated.totalTime = total

        // 카탈로그 갱신
        if let idx = ModelCatalog.shared.models.firstIndex(where: { $0.id == model.id && $0.provider == model.provider }) {
            ModelCatalog.shared.models[idx].ttft = ttft
            ModelCatalog.shared.models[idx].totalTime = total
        }
        return updated
    }

    // MARK: - 전체(구성된 공급자만) 벤치마크
    func benchmarkAll(models: [AIModel]) async {
        isRunning = true
        defer { isRunning = false }
        for model in models {
            runningModelID = model.id
            _ = await benchmark(model: model)
        }
        runningModelID = nil
    }

    // MARK: - 랭킹 (TTFT 오름차순, 측정된 모델만)
    func rankedModels() -> [AIModel] {
        ModelCatalog.shared.models
            .filter { $0.ttft != nil }
            .sorted { ($0.ttft ?? .infinity) < ($1.ttft ?? .infinity) }
    }
}