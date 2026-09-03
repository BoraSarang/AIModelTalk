import Foundation

/// 평가(Eval) 그리드 셀 — 프롬프트×모델 교차점의 실행 상태와 측정 (v0.2.0 T-203)
struct EvalCell: Identifiable, Equatable {
    let id: UUID = UUID()
    let prompt: String
    let model: AIModel
    var state: EvalState = .idle
    var ttft: TimeInterval?
    var totalTime: TimeInterval?
    var promptTokens: Int?
    var completionTokens: Int?
    var text: String = ""

    enum EvalState: Equatable {
        case idle          // 대기
        case run
        case done          // 완료
        case failed(String)

        var isDone: Bool {
            if case .done = self { return true }
            return false
        }

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    /// 초당 출력 토큰 — 완료 토큰 ÷ 총 시간 (없으면 nil)
    var tokensPerSecond: Double? {
        guard let ct = completionTokens, ct > 0, let t = totalTime, t > 0 else { return nil }
        return Double(ct) / t
    }
}

/// 회귀 추적용 실행 기록 — UserDefaults에 저장 (v0.2.0 T-203)
struct EvalRunRecord: Codable, Identifiable {
    let id: UUID = UUID()
    let timestamp: Date
    var cells: [CellRecord]

    struct CellRecord: Codable, Hashable {
        let prompt: String
        let modelID: String
        let providerRaw: String
        var score: Int?          // 사용자 점수(1~10) — 회귀 비교 대상
        var ttft: TimeInterval?
        var totalTime: TimeInterval?
        var completionTokens: Int?
    }
}

/// 평가(Eval) 그리드 서비스 (v0.2.0 T-203)
/// 프롬프트×모델 매트릭스를 최대 5개 모델씩 병렬 실행하고, 셀별 TTFT·tok/s·점수(1~10)를
/// 기록해 회귀 추적과 CSV/Markdown 내보내기를 제공한다.
@MainActor
final class EvalService: ObservableObject {
    static let shared = EvalService()

    @Published var prompts: [String] = [EvalService.defaultPrompt]
    @Published var selectedModelIDs: Set<String> = []
    @Published var cells: [EvalCell] = []
    @Published var isRunning = false

    /// 셀별 사용자 점수(1~10) — EvalCell.id → 점수 (UI 바인딩용)
    @Published var scores: [UUID: Int] = [:]
    /// 최근 실행 내역 — 회귀 추적용 (최신순)
    @Published private(set) var history: [EvalRunRecord] = []

    static let defaultPrompt = "대한민국의 수도는 어디인가요? 한 문장으로 답하세요."

    private let storageKey = "evalRunHistory_v1"

    init() {
        loadHistory()
    }

    // MARK: - 구성

    /// 프롬프트 한 줄 추가 (빈 값 무시)
    func addPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        prompts.append(trimmed)
    }

    func removePrompt(at index: Int) {
        guard !isRunning, prompts.indices.contains(index) else { return }
        prompts.remove(at: index)
    }

    // MARK: - 실행 (5-at-a-time 병렬)

    /// 선택 모델 목록 (카탈로그에서 파생)
    var selectedModels: [AIModel] {
        ModelCatalog.shared.models.filter { selectedModelIDs.contains($0.id) }
    }

    func run() {
        let models = selectedModels
        let promptList = prompts
        guard !models.isEmpty, !promptList.isEmpty, !isRunning else { return }

        isRunning = true
        prepareCells(prompts: promptList, models: models)
        scores = [:]

        let groupSize = 5 // 5-at-a-time 병렬

        let taskGroupWork: ([AIModel]) async -> Void = { modelChunk in
            await withTaskGroup(of: Void.self) { group in
                for model in modelChunk {
                    group.addTask { [weak self] in
                        await self?.runModel(model: model, prompts: promptList)
                    }
                }
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let chunks = stride(from: 0, to: models.count, by: groupSize).map {
                Array(models[$0..<min($0 + groupSize, models.count)])
            }
            for chunk in chunks {
                await taskGroupWork(chunk)
            }
            self.isRunning = false
            self.persist()
            DebugLogger.shared.info("EVAL", "[FEATURE] 평가 실행 완료: 프롬프트 \(promptList.count)개 × 모델 \(models.count)개")
        }
    }

    private func prepareCells(prompts: [String], models: [AIModel]) {
        cells = []
        for prompt in prompts {
            for model in models {
                cells.append(EvalCell(prompt: prompt, model: model))
            }
        }
    }

    private func runModel(model: AIModel, prompts: [String]) async {
        guard let client = try? AIClientFactory.client(provider: model.provider, modelID: model.id) else {
            markFailed(model: model, reason: "[E-MAC-KEY-1001] API 키가 없습니다")
            return
        }

        for prompt in prompts {
            guard let idx = index(of: prompt, model: model) else { continue }
            cells[idx].state = .run
            let start = Date()
            do {
                let capture = UsageCapture()
                let stream = client.stream(
                    messages: [ChatMessage(role: .user, content: prompt)],
                    systemPrompt: nil,
                    temperature: nil) { promptTokens, completionTokens in
                        capture.promptTokens = promptTokens
                        capture.completionTokens = completionTokens
                    }
                var text = ""
                for try await chunk in stream {
                    if cells[idx].ttft == nil {
                        cells[idx].ttft = Date().timeIntervalSince(start)
                    }
                    text += chunk
                }
                cells[idx].totalTime = Date().timeIntervalSince(start)
                cells[idx].promptTokens = capture.promptTokens
                cells[idx].completionTokens = capture.completionTokens
                cells[idx].text = text
                cells[idx].state = text.isEmpty ? .failed("응답 없음") : .done
            } catch let error as AppError {
                let disabled = ModelCatalog.shared.disableUnavailableModel(error: error, model: model)
                cells[idx].state = .failed("\(error.localizedDescription)\(disabled ? " (목록에서 자동 제외됨)" : "")")
            } catch {
                cells[idx].state = .failed("알 수 없는 오류")
            }
        }
    }

    private func markFailed(model: AIModel, reason: String) {
        for i in cells.indices where cells[i].model.id == model.id && cells[i].model.provider == model.provider {
            cells[i].state = .failed(reason)
        }
    }

    private func index(of prompt: String, model: AIModel) -> Int? {
        cells.firstIndex { $0.prompt == prompt && $0.model.id == model.id && $0.model.provider == model.provider }
    }

    // MARK: - 정렬·필터

    enum SortKey { case model, prompt, ttft, tokensPerSecond, score }

    struct EvalFilter {
        var modelID: String? = nil
        var promptContains: String? = nil
    }

    /// 정렬·필터 적용된 셀 (기본: 최근 실행 순서 유지)
    func filteredCells(filter: EvalFilter = EvalFilter(), sort: SortKey = .model) -> [EvalCell] {
        var list = cells
        if let mid = filter.modelID {
            list = list.filter { $0.model.id == mid }
        }
        if let kw = filter.promptContains, !kw.isEmpty {
            list = list.filter { $0.prompt.localizedCaseInsensitiveContains(kw) }
        }
        switch sort {
        case .ttft:
            list.sort { ($0.ttft ?? .infinity) < ($1.ttft ?? .infinity) }
        case .tokensPerSecond:
            list.sort { ($0.tokensPerSecond ?? -1) > ($1.tokensPerSecond ?? -1) }
        case .score:
            list.sort { (scores[$0.id] ?? 0) > (scores[$1.id] ?? 0) }
        case .prompt:
            list.sort { $0.prompt < $1.prompt }
        case .model:
            break // 원래 순서
        }
        return list
    }

    /// 모델 반환 (카탈로그 순서 유지)
    var displayModels: [AIModel] {
        selectedModels
    }

    // MARK: - 점수 편집

    func setScore(cellID: UUID, value: Int?) {
        guard let v = value else { scores[cellID] = nil; return }
        scores[cellID] = min(max(v, 1), 10)
    }

    // MARK: - 회귀 추적

    /// 특정 (프롬프트, 모델) 셀의 직전 실행 점수 — 이전 실행 대비 회귀 표시용
    func previousScore(prompt: String, model: AIModel) -> Int? {
        Self.previousScore(from: history, prompt: prompt, modelID: model.id, providerRaw: model.provider.rawValue)
    }

    /// 최신 실행(history[0]) 점수 — 회귀 로직 헬퍼
    func latestScore(prompt: String, model: AIModel) -> Int? {
        Self.latestScore(from: history, prompt: prompt, modelID: model.id, providerRaw: model.provider.rawValue)
    }

    /// 순수 정적 회귀 조회 — 가장 오래된 이전 실행에서 점수 반환 (회귀 테스트·로직 재사용)
    static func previousScore(from records: [EvalRunRecord], prompt: String, modelID: String, providerRaw: String) -> Int? {
        guard records.count >= 2 else { return nil }
        for record in records.dropFirst() {
            if let c = record.cells.first(where: { $0.prompt == prompt && $0.modelID == modelID && $0.providerRaw == providerRaw }),
               let s = c.score {
                return s
            }
        }
        return nil
    }

    static func latestScore(from records: [EvalRunRecord], prompt: String, modelID: String, providerRaw: String) -> Int? {
        guard let r = records.first else { return nil }
        return r.cells.first(where: { $0.prompt == prompt && $0.modelID == modelID && $0.providerRaw == providerRaw })?.score
    }

    func persist() {
        let record = EvalRunRecord(
            timestamp: Date(),
            cells: cells.map { c in
                EvalRunRecord.CellRecord(
                    prompt: c.prompt,
                    modelID: c.model.id,
                    providerRaw: c.model.provider.rawValue,
                    score: scores[c.id],
                    ttft: c.ttft,
                    totalTime: c.totalTime,
                    completionTokens: c.completionTokens)
            })
        if history.isEmpty || history[0].timestamp < record.timestamp {
            history.insert(record, at: 0)
        }
        let limit = 20
        if history.count > limit { history = Array(history.prefix(limit)) }
        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([EvalRunRecord].self, from: data) else { return }
        history = decoded
    }

    // MARK: - 내보내기

    /// CSV — BOM 포함(Excel 한글 깨짐 방지), 모든 셀을 승자/실행 순으로 나열
    func exportCSV() -> String {
        var rows: [[String]] = [["프롬프트", "모델", "점수", "TTFT(ms)", "총시간(s)", "tok/s", "완료토큰", "상태"]]
        for c in cells {
            let score = scores[c.id].map(String.init) ?? ""
            let ttft = c.ttft.map { String(format: "%.0f", $0 * 1000) } ?? ""
            let total = c.totalTime.map { String(format: "%.2f", $0) } ?? ""
            let tps = c.tokensPerSecond.map { String(format: "%.1f", $0) } ?? ""
            let ct = c.completionTokens.map(String.init) ?? ""
            let state = stateText(c)
            rows.append([c.prompt, c.model.displayName, score, ttft, total, tps, ct, state])
        }
        return rows.map { $0.joined(separator: ",") }.joined(separator: "\n")
    }

    /// Markdown 테이블 — cells에서 실제 사용된 모델·프롬프트 기준 (카탈로그 독립)
    func exportMarkdown() -> String {
        // 셀에 등장한 모델과 프롬프트를 순서대로 추출 (중복 제거)
        var models: [AIModel] = []
        var promptList: [String] = []
        for c in cells {
            if !models.contains(where: { $0.id == c.model.id && $0.provider == c.model.provider }) {
                models.append(c.model)
            }
            if !promptList.contains(c.prompt) {
                promptList.append(c.prompt)
            }
        }

        var lines: [String] = []
        let modelNames = models.map(\.displayName)
        let headers = ["프롬프트"] + modelNames
        lines.append("| " + headers.joined(separator: " | ") + " |")
        lines.append("| " + modelNames.map { _ in "---" }.joined(separator: " | ") + " |")

        for prompt in promptList {
            var row = [prompt]
            for model in models {
                if let c = cells.first(where: { $0.prompt == prompt && $0.model.id == model.id && $0.model.provider == model.provider }) {
                    row.append(cellSummary(c))
                } else {
                    row.append("-")
                }
            }
            lines.append("| " + row.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    private func cellSummary(_ c: EvalCell) -> String {
        let score = scores[c.id].map { "\($0)점" } ?? "·"
        let ttft = c.ttft.map { String(format: "%.0fms", $0 * 1000) } ?? "-"
        return "\(score) / TTFT \(ttft)"
    }

    private func stateText(_ c: EvalCell) -> String {
        switch c.state {
        case .idle: return "대기"
        case .run: return "실행 중"
        case .done: return "완료"
        case .failed: return "실패"
        }
    }
}