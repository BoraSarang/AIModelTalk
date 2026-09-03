import Foundation

struct ComparisonResult: Identifiable {
    let id: UUID = UUID()
    let model: AIModel
    var text: String = ""
    var isStreaming: Bool = false
    var ttft: TimeInterval?
    var totalTime: TimeInterval?
    var error: String?
    /// API 실측 토큰 (v1.9 T-78 완결 — T-76 파이프라인 재사용)
    var promptTokens: Int?
    var completionTokens: Int?

    /// 답변 글자 수 — 리포트 표시용
    var answerLength: Int { text.count }

    /// 초당 출력 토큰 (T-202 성능 메트릭) — 실측 완료 토큰 / 총 응답 시간
    var tokensPerSecond: Double? {
        guard let ct = completionTokens, ct > 0, let t = totalTime, t > 0 else { return nil }
        return Double(ct) / t
    }
}

/// 판정 모델의 루브릭 채점 결과 (v1.9 T-87)
/// 항목별 0~10점 — 정확성/명확성/깊이/한국어 자연스러움/속도 체감/종합
struct JudgeScore: Identifiable, Codable {
    var id: String { model }
    let model: String             // 모델 식별자 — 후보 번호("[1]") 또는 표시명
    let accuracy: Double          // 정확성
    let clarity: Double           // 명확성
    let depth: Double             // 깊이
    let koreanFluency: Double     // 한국어 자연스러움
    let speedFeel: Double         // 속도 체감 (실측 시간 참고)
    let overall: Double           // 종합
    let comment: String           // 한줄평

    enum CodingKeys: String, CodingKey {
        case model, accuracy, clarity, depth, overall, comment
        case koreanFluency = "korean_fluency"
        case speedFeel = "speed_feel"
        case koreanFluencyAlt = "koreanFluency"   // LLM 키 변형 폴백
        case speedFeelAlt = "speedFeel"
    }

    init(model: String = "", accuracy: Double = 0, clarity: Double = 0, depth: Double = 0,
         koreanFluency: Double = 0, speedFeel: Double = 0, overall: Double = 0, comment: String = "") {
        self.model = model
        self.accuracy = accuracy
        self.clarity = clarity
        self.depth = depth
        self.koreanFluency = koreanFluency
        self.speedFeel = speedFeel
        self.overall = overall
        self.comment = comment
    }

    /// 필드 누락·키 변형 방어 — 실측에서 comment 생략으로 전체 파싱이 실패한 사례 대응 (v1.9 T-88)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        accuracy = Self.number(in: c, .accuracy)
        clarity = Self.number(in: c, .clarity)
        depth = Self.number(in: c, .depth)
        if let v = try c.decodeIfPresent(Double.self, forKey: .koreanFluency) {
            koreanFluency = v
        } else {
            koreanFluency = Self.number(in: c, .koreanFluencyAlt)
        }
        if let v = try c.decodeIfPresent(Double.self, forKey: .speedFeel) {
            speedFeel = v
        } else {
            speedFeel = Self.number(in: c, .speedFeelAlt)
        }
        overall = Self.number(in: c, .overall)
        comment = try c.decodeIfPresent(String.self, forKey: .comment) ?? ""
    }

    /// 인코딩은 표준 키만 사용 (alt 폴백 키는 디코딩 전용)
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(accuracy, forKey: .accuracy)
        try c.encode(clarity, forKey: .clarity)
        try c.encode(depth, forKey: .depth)
        try c.encode(koreanFluency, forKey: .koreanFluency)
        try c.encode(speedFeel, forKey: .speedFeel)
        try c.encode(overall, forKey: .overall)
        try c.encode(comment, forKey: .comment)
    }

    /// 정수/실수/숫자문자열 양쪽 허용 + 누락 시 0
    /// (SE-0230: try? decodeIfPresent는 이미 플래트닝된 Optional 반환 — 단일 바인딩 필수)
    private static func number(in c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double {
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return v }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key),
           let v = Double(s.trimmingCharacters(in: .whitespaces)) { return v }
        return 0
    }
}

/// 판정 모델 응답 페이로드 — 요약 문단 + 채점 + 승자
struct JudgeVerdictPayload: Codable {
    let summary: String
    let scores: [JudgeScore]
    let winner: String

    private enum Keys: String, CodingKey { case summary, scores, winner }

    /// summary/winner/scores 누락 허용 (v1.9 T-88)
    init(summary: String = "", scores: [JudgeScore] = [], winner: String = "") {
        self.summary = summary
        self.scores = scores
        self.winner = winner
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        scores = try c.decodeIfPresent([JudgeScore].self, forKey: .scores) ?? []
        winner = try c.decodeIfPresent(String.self, forKey: .winner) ?? ""
    }
}

@MainActor
final class ComparisonService: ObservableObject {
    static let shared = ComparisonService()

    @Published var results: [ComparisonResult] = []
    @Published var question: String = ""
    @Published var isRunning: Bool = false
    @Published var judgeSummary: String = ""
    @Published var isJudging: Bool = false
    /// 합성 답변 (T-206) — 판정 모델이 여러 후보를 병합한 한 답변
    @Published var synthesisText: String = ""
    @Published var isSynthesizing: Bool = false
    /// 루브릭 채점 — 파싱 성공 시 채워지고, 실패 시 judgeSummary 텍스트로 폴백 (v1.9 T-87)
@Published var reportScores: [JudgeScore] = []
    @Published var winnerName: String? = nil
    /// 비교 실행 시 지정할 모델 파라미터 (T-202) — 전부 nil이면 공급자 기본값
    var params: ModelParams = .none

    func run(models: [AIModel]) async {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !models.isEmpty else { return }

        results = models.map { ComparisonResult(model: $0, isStreaming: true) }
        judgeSummary = ""
        reportScores = []
        winnerName = nil
        isRunning = true
        defer { isRunning = false }

        await withTaskGroup(of: Void.self) { group in
            for idx in results.indices {
                group.addTask { [weak self] in
                    await self?.streamOne(index: idx)
                }
            }
        }

        if AppSettings.shared.showJudgeSummary {
            await runJudge()
        }
        if AppSettings.shared.showSynthesis {
            await synthesize()
        }
    }

    /// 대화 컨텍스트 기반 병렬 비교 (T-201) — 기존 단일 질문 비교와 달리
    /// `context`(대화 이력)를 모든 래인에 동일 적용해 나란히 스트리밍한다.
    /// 채점·승자 판정은 기존 runJudge 논리를 컨텍스트 버전으로 재사용한다.
    func run(context: [ChatMessage], systemPrompt: String?, temperature: Double?, models: [AIModel]) async {
        await run(context: context, systemPrompt: systemPrompt,
                  params: ModelParams(temperature: temperature, topP: nil, maxTokens: nil),
                  models: models)
    }

    /// 대화 컨텍스트 + 모델 파라미터 기반 병렬 비교 (T-202)
    func run(context: [ChatMessage], systemPrompt: String?, params: ModelParams, models: [AIModel]) async {
        guard !models.isEmpty else { return }

        results = models.map { ComparisonResult(model: $0, isStreaming: true) }
        judgeSummary = ""
        reportScores = []
        winnerName = nil
        isRunning = true
        defer { isRunning = false }

        let ctx = context
        let sys = systemPrompt
        let p = params
        self.params = p

        await withTaskGroup(of: Void.self) { group in
            for idx in results.indices {
                group.addTask { [weak self] in
                    await self?.streamOne(index: idx, context: ctx, systemPrompt: sys, params: p)
                }
            }
        }

        // 판정 프롬프트가 사용할 '질문' — 대화 컨텍스트의 마지막 사용자 메시지로 보정 (T-201)
        if let lastUser = ctx.last(where: { $0.role == .user }) {
            question = lastUser.content
        }
        if AppSettings.shared.showJudgeSummary {
            await runJudge()
        }
        if AppSettings.shared.showSynthesis {
            await synthesize()
        }
    }

    /// 비교 실행 중 여부 — true면 메시지 리스트 하단에 비교 결과 그리드 오버레이
    func stopAll() {
        isRunning = false
        for idx in results.indices {
            results[idx].isStreaming = false
        }
        DebugLogger.shared.info("COMPARE", "[FEATURE] 비교 중단: \(results.count)개 래인 종료")
    }

    private func streamOne(index: Int) async {
        await streamOne(index: index, context: [ChatMessage(role: .user, content: question)], systemPrompt: nil, params: params)
    }

    private func streamOne(index: Int, context: [ChatMessage], systemPrompt: String?, params: ModelParams) async {
        let model = results[index].model
        guard let client = try? AIClientFactory.client(provider: model.provider, modelID: model.id) else {
            results[index].isStreaming = false
            results[index].error = "[E-MAC-KEY-1001] \(model.provider.rawValue) API 키가 없습니다."
            return
        }

        let messages = context
        let start = Date()
        do {
            let capture = UsageCapture()
            let stream = client.stream(messages: messages, systemPrompt: systemPrompt,
                                       temperature: params.temperature, topP: params.topP, maxTokens: params.maxTokens) { prompt, completion in
                capture.promptTokens = prompt
                capture.completionTokens = completion
            }
            for try await chunk in stream {
                if results[index].ttft == nil {
                    results[index].ttft = Date().timeIntervalSince(start)
                }
                results[index].text += chunk
            }
            results[index].totalTime = Date().timeIntervalSince(start)
            results[index].promptTokens = capture.promptTokens
            results[index].completionTokens = capture.completionTokens
        } catch let error as AppError {
            let disabled = ModelCatalog.shared.disableUnavailableModel(error: error, model: results[index].model)
            let suffix = disabled ? " (목록에서 자동 제외됨)" : ""
            results[index].error = "\(error.localizedDescription)\(suffix)"
        } catch {
            results[index].error = "알 수 없는 오류"
        }
        results[index].isStreaming = false
    }

    // MARK: - 판정 모델 리포트 (v1.9 T-87 루브릭 채점)

    private func runJudge() async {
        guard let judge = judgeModel() else { return }
        guard let client = try? AIClientFactory.client(provider: judge.provider, modelID: judge.id) else { return }

        isJudging = true
        defer { isJudging = false }

        DebugLogger.shared.info("COMPARE", "판정 시작: \(judge.displayName), 대상 \(results.count)개")

        var prompt = """
        당신은 AI 답변 심사위원입니다. 같은 질문에 대한 여러 모델의 답변과 실측 데이터를 평가하세요.
        반드시 아래 형식의 JSON만 출력하세요. 코드펜스나 다른 설명은 절대 포함하지 마세요.

        질문: \(question)

        """
        for (index, r) in results.enumerated() {
            let ttft = r.ttft.map { String(format: "%.2f초", $0) } ?? "측정실패"
            let total = r.totalTime.map { String(format: "%.2f초", $0) } ?? "측정실패"
            let err = r.error != nil ? " [응답 오류 발생]" : ""
            prompt += "\n--- 후보[\(index + 1)] \(r.model.displayName) (실측: 첫응답 \(ttft), 총 \(total))\(err) ---\n\(r.text)\n"
        }
        prompt += """

        JSON 형식:
        {"summary":"전체 비교 요약 3~5문장","scores":[{"model":"1","accuracy":0,"clarity":0,"depth":0,"korean_fluency":0,"speed_feel":0,"overall":0,"comment":"한줄평"}],"winner":"가장 좋은 후보의 번호"}

        규칙:
        - summary와 comment는 반드시 한국어로 작성하세요. 영어 사용 금지
        - "model"과 "winner"에는 반드시 위 대괄호 안의 후보 번호만 문자열로 넣으세요 (예: "1"). 표시명을 쓰지 마세요
        - accuracy(정확성)/clarity(명확성)/depth(깊이)/korean_fluency(한국어 자연스러움)/overall(종합)은 답변 품질 평가
        - speed_feel(속도 체감)은 실측 시간을 반영해 평가
        - 각 점수는 0~10 (소수 허용). scores 배열에는 모든 후보가 포함되어야 함
        """

        judgeSummary = ""
        reportScores = []
        winnerName = nil
        do {
            var raw = ""
            let stream = client.stream(messages: [ChatMessage(role: .user, content: prompt)], systemPrompt: nil)
            for try await chunk in stream {
                raw += chunk
            }

            if let payload = Self.parseVerdict(raw), !payload.scores.isEmpty {
                reportScores = payload.scores
                winnerName = Self.resolveWinnerName(payload.winner, results: results)
                judgeSummary = payload.summary
                DebugLogger.shared.info("COMPARE", "[FEATURE] 비교 리포트 생성 성공: 채점 \(payload.scores.count)건, 승자 '\(winnerName ?? "미지정")'")
            } else {
                // JSON 파싱 실패 폴백 — 기존처럼 원문 텍스트를 요약으로 표시
                judgeSummary = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if judgeSummary.isEmpty { judgeSummary = "판정 응답이 비어 있습니다." }
                DebugLogger.shared.warn("COMPARE", "[E-MAC-API-1002] 리포트 JSON 파싱 실패 — 텍스트 요약으로 폴백")
            }
        } catch let error as AppError {
            // 판정 모델이 EOL(410)/모델 없음(404)이면 자동 비활성화하고, 다음 호출에서 다른 후보를 쓰도록 안내.
            // 같은 run() 내에서의 재시도는 복잡도를 피하고, 다음 비교 때 자동 재선택된다.
            let disabled = ModelCatalog.shared.disableUnavailableModel(error: error, model: judge)
            judgeSummary = "[\(error.errorCode)] 판정 실패: \(error.localizedDescription ?? "")"
                + (disabled ? " — 판정 모델이 목록에서 자동 제외됨" : "")
            DebugLogger.shared.error("COMPARE", "판정 스트리밍 실패: \(judge.displayName)")
        } catch {
            judgeSummary = "판정 실패"
            DebugLogger.shared.error("COMPARE", "판정 중 알 수 없는 오류")
        }
    }

    // MARK: - 파싱/순위 헬퍼 (테스트 가능하도록 nonisolated static)

    /// 판정 응답에서 JSON 추출·디코딩 — 코드펜스/주변 잡음 방어
    nonisolated static func parseVerdict(_ raw: String) -> JudgeVerdictPayload? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            if let firstLineEnd = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstLineEnd)...])
            }
            if let fenceEnd = text.range(of: "```", options: .backwards) {
                text = String(text[..<fenceEnd.lowerBound])
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JudgeVerdictPayload.self, from: data)
    }

    /// "1", "[2]", "#3" 같은 순수 인덱스 문자열만 번호로 해석 — 모델명 속 숫자(GPT-OSS-20B 등)와 구분 (v1.9 T-88)
    nonisolated static func pureIndexValue(_ text: String) -> Int? {
        var inner = text.trimmingCharacters(in: .whitespaces)
        if inner.hasPrefix("["), let end = inner.firstIndex(of: "]") {
            inner = String(inner[inner.index(after: inner.startIndex)..<end])
        } else if inner.hasPrefix("#") {
            inner = String(inner.dropFirst())
        }
        guard !inner.isEmpty, inner.allSatisfy(\.isNumber) else { return nil }
        return Int(inner)
    }

    /// 채점 항목을 후보에 매칭 — 번호 우선 → 표시명 정확 일치 → 유일한 포함 일치 (v1.9 T-88)
    nonisolated static func scoreFor(_ result: ComparisonResult, index: Int, scores: [JudgeScore]) -> JudgeScore? {
        if let s = scores.first(where: { pureIndexValue($0.model) == index + 1 }) {
            return s
        }
        if let s = scores.first(where: { $0.model.trimmingCharacters(in: .whitespaces) == result.model.displayName }) {
            return s
        }
        let contains = scores.filter {
            $0.model.localizedCaseInsensitiveContains(result.model.displayName)
                || result.model.displayName.localizedCaseInsensitiveContains($0.model)
        }
        return contains.count == 1 ? contains[0] : nil
    }

    /// 승자 문자열 해석 — 번호("2") 또는 표시명 모두 허용 (v1.9 T-88)
    nonisolated static func resolveWinnerName(_ raw: String, results: [ComparisonResult]) -> String? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let n = pureIndexValue(t), results.indices.contains(n - 1) {
            return results[n - 1].model.displayName
        }
        if let exact = results.first(where: { $0.model.displayName == t }) {
            return exact.model.displayName
        }
        return results.first {
            $0.model.displayName.localizedCaseInsensitiveContains(t)
                || t.localizedCaseInsensitiveContains($0.model.displayName)
        }?.model.displayName
    }

    /// 리포트 행(원본 인덱스 포함) 정렬 — 종합 점수 내림차순,
    /// 동점이면 speed_feel 내림차순 → 실측 총시간 오름차순 타이브레이커 (v1.9 T-88)
    nonisolated static func rankedEntries(_ results: [ComparisonResult], scores: [JudgeScore]) -> [(index: Int, result: ComparisonResult)] {
        let indexed = Array(results.enumerated())
        guard !scores.isEmpty else {
            return indexed.sorted { lhs, rhs in
                switch (lhs.element.error == nil, rhs.element.error == nil) {
                case (true, false): return true
                case (false, true): return false
                default:
                    return (lhs.element.totalTime ?? .infinity) < (rhs.element.totalTime ?? .infinity)
                }
            }.map { ($0.offset, $0.element) }
        }

        return indexed.sorted { lhs, rhs in
            let l = scoreFor(lhs.element, index: lhs.offset, scores: scores)?.overall ?? -1
            let r = scoreFor(rhs.element, index: rhs.offset, scores: scores)?.overall ?? -1
            if l != r { return l > r }
            let ls = scoreFor(lhs.element, index: lhs.offset, scores: scores)?.speedFeel ?? -1
            let rs = scoreFor(rhs.element, index: rhs.offset, scores: scores)?.speedFeel ?? -1
            if ls != rs { return ls > rs }
            return (lhs.element.totalTime ?? .infinity) < (rhs.element.totalTime ?? .infinity)
        }.map { ($0.offset, $0.element) }
    }

    /// 기존 시그니처 호환용 — 결과 배열만 반환
    nonisolated static func rankedResults(_ results: [ComparisonResult], scores: [JudgeScore]) -> [ComparisonResult] {
        rankedEntries(results, scores: scores).map(\.result)
    }

    private func judgeModel() -> AIModel? {
        // 호출 가능한 첫 모델을 판정자로 사용 (NVIDIA 우선, 사용자 지정 공급자 우선)
        // v1.9 T-85: 커스텀 엔드포인트와 Ollama도 후보에 포함, T-206: judgeProviderRaw 우선
        let endpoints = CustomEndpointStore(defaults: CustomEndpointStore.suiteDefaults).endpoints
        let preferredRaw = AppSettings.shared.judgeProviderRaw
        var candidates = ModelCatalog.shared.models.filter { model in
            switch model.provider {
            case .ollama:
                return true // 서버 다운이면 runJudge에서 에러 표시
            case .appleIntelligence:
                return AppleIntelligenceSupport.modelAvailable // v2.1 T-96
            case .custom:
                if let eid = model.customEndpointID,
                   let endpoint = endpoints.first(where: { $0.id == eid }) {
                    return !endpoint.baseURL.isEmpty // 무인증 로컬 서버 허용
                }
                return !AppSettings.shared.customAPIKey.isEmpty // 구형 프리픽스 없는 모델 폴백
            default:
                return !AppSettings.shared.apiKey(for: model.provider).isEmpty
            }
        }
        // 선택 공급자가 지정되면 해당 provider부터 우선
        if let preferredRaw,
           let preferred = candidates.enumerated().first(where: { $0.element.provider.rawValue == preferredRaw }) {
            return candidates[preferred.offset]
        }
        let judge = candidates.first { $0.provider == .nvidia } ?? candidates.first
        if let judge {
            DebugLogger.shared.info("COMPARE", "판정 모델 선택: \(judge.provider.rawValue)/\(judge.displayName)")
        }
        return judge
    }

    // MARK: - 합성 답변 (T-206)

    /// 판정 모델(공급자 우선)이 여러 후보를 병합해 최선의 답변 한 개를 생성
    func synthesize() async {
        guard !results.isEmpty else { return }
        guard let judge = judgeModel() else { return }
        guard let client = try? AIClientFactory.client(provider: judge.provider, modelID: judge.id) else {
            synthesisText = "합성에 사용할 판정 모델을 찾을 수 없습니다."
            return
        }
        isSynthesizing = true
        defer { isSynthesizing = false }

        DebugLogger.shared.info("COMPARE", "[FEATURE] 합성 시작: \(judge.displayName), 후보 \(results.count)개")
        var prompt = """
        당신은 AI 답변 통합 전문가입니다. 같은 질문에 대한 여러 모델의 답변을 읽고 가장 정확·깔끔한 답변을 선택하되, \
        부족한 부분은 다른 답변에서 보완해 하나의 완성된 답변으로 작성하세요.
        반드시 질문에 대한 실제 답변 본문만 한국어로 출력하세요. 도입부나 설명·표기 없이 답변만 주세요.

        질문: \(question)

        """
        for (index, r) in results.enumerated() where r.error == nil && !r.text.isEmpty {
            prompt += "\n--- 후보[\(index + 1)] \(r.model.displayName) ---\n\(r.text)\n"
        }
        if results.allSatisfy({ $0.error != nil || $0.text.isEmpty }) {
            synthesisText = "응답에 성공한 후보가 없어 합성을 만들 수 없습니다."
            return
        }

        do {
            var raw = ""
            let stream = client.stream(messages: [ChatMessage(role: .user, content: prompt)], systemPrompt: nil)
            for try await chunk in stream {
                raw += chunk
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            synthesisText = trimmed.isEmpty ? "합성 응답이 비어 있습니다." : trimmed
            DebugLogger.shared.info("COMPARE", "합성 완료: \(synthesisText.count)자")
        } catch let error as AppError {
            let disabled = ModelCatalog.shared.disableUnavailableModel(error: error, model: judge)
            synthesisText = "[\(error.errorCode)] 합성 실패: \(error.localizedDescription ?? "")"
                + (disabled ? " — 합성 모델이 목록에서 자동 제외됨" : "")
            DebugLogger.shared.error("COMPARE", "합성 스트리밍 실패: \(judge.displayName)")
        } catch {
            synthesisText = "합성 실패"
            DebugLogger.shared.error("COMPARE", "합성 중 알 수 없는 오류")
        }
    }

    // MARK: - 텍스트 Diff (T-206)

    /// 라인 단위 Diff 연산 — 순수 함수 (LCS 기반). 공통/추가/제거 라인 목록 반환.
    nonisolated static func textDiff(before: String, after: String) -> [DiffLine] {
        let a = before.components(separatedBy: "\n")
        let b = after.components(separatedBy: "\n")
        let table = lcsTable(a, b)
        var result: [DiffLine] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count && j < b.count && a[i] == b[j] {
                result.append(DiffLine(kind: .same, text: a[i]))
                i += 1; j += 1
            } else if j < b.count && (i == a.count || lookup(table, i: i + 1, j: j) >= lookup(table, i: i, j: j + 1)) {
                result.append(DiffLine(kind: .added, text: b[j]))
                j += 1
            } else if i < a.count {
                result.append(DiffLine(kind: .removed, text: a[i]))
                i += 1
            } else {
                break
            }
        }
        return result
    }

    /// LCS 길이 표
    private nonisolated static func lcsTable(_ a: [String], _ b: [String]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        return table
    }

    private nonisolated static func lookup(_ t: [[Int]], i: Int, j: Int) -> Int {
        guard i < t.count, j < t[i].count else { return 0 }
        return t[i][j]
    }
}

/// Diff 라인 유형 (T-206)
enum DiffKind: Equatable {
    case same, added, removed
}

/// Diff 라인 한 줄 (T-206)
struct DiffLine: Equatable {
    let kind: DiffKind
    let text: String
}