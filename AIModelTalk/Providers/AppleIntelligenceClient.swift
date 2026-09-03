import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence 지원 상태 헬퍼 — 팩토리·설정 화면 공용 (v2.0 T-79)
enum AppleIntelligenceSupport {
    /// OS 자체 지원 여부 (macOS 26+)
    static var osSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// 시스템 모델 가용성 — OS 지원 시 FoundationModels로 실확인
    static var modelAvailable: Bool {
        guard osSupported else { return false }
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
            return false
        }
        return false
    }

    static var unavailableReason: String {
        guard osSupported else { return "macOS 26 이상이 필요합니다." }
        return "Apple Intelligence가 이 기기에서 사용 불가합니다. (시스템 설정 → Apple Intelligence 확인)"
    }
}

/// Apple Intelligence 온디바이스 클라이언트 (v2.0 T-79)
/// macOS 26+ FoundationModels — 무료·온디바이스, usage 미보고(비용 $0)
struct AppleIntelligenceClient: ChatClient {
    func stream(messages: [ChatMessage], systemPrompt: String?, onUsage: ((Int?, Int?) -> Void)?) -> AsyncThrowingStream<String, Error> {
        DebugLogger.shared.info("APP", "[FEATURE] Apple Intelligence 스트리밍 진입: 메시지 \(messages.count)개")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard #available(macOS 26.0, *) else {
                        DebugLogger.shared.error("APP", "[E-MAC-AI-1001] OS 미지원 — macOS 26 필요")
                        throw AppError.unsupportedFeature("Apple Intelligence는 macOS 26 이상에서 사용할 수 있습니다.")
                    }

                    // 시스템 모델 가용성 게이트 (기기 미지원/설정 OFF/지역 제한)
                    if case .available = SystemLanguageModel.default.availability {
                        // 사용 가능
                    } else {
                        DebugLogger.shared.error("APP", "[E-MAC-AI-1002] 시스템 모델 사용 불가: \(SystemLanguageModel.default.availability)")
                        throw AppError.unsupportedFeature(AppleIntelligenceSupport.unavailableReason)
                    }

                    let session = LanguageModelSession(instructions: systemPrompt ?? "")
                    let prompt = Self.buildTrimmedPrompt(from: messages).prompt
                    let options = GenerationOptions(temperature: 0.7)

                    DebugLogger.shared.info("APP", "Apple Intelligence 스트리밍 시작 (\(prompt.count)자 프롬프트)")
                    let startTime = Date()

                    let responseStream = session.streamResponse(to: prompt, options: options)
                    // FoundationModels 스트리밍은 매 청크가 "누적 전문"이므로 델타만 발행해야 한다 (v2.1 T-104)
                    // 누적값을 그대로 이어붙이면 응답이 제곱으로 불어나는 버그 수정
                    var previousCount = 0
                    for try await partial in responseStream {
                        let accumulated = partial.content
                        guard accumulated.count > previousCount else { continue }
                        continuation.yield(String(accumulated.dropFirst(previousCount)))
                        previousCount = accumulated.count
                    }
                    let totalChars = previousCount

                    let elapsed = Date().timeIntervalSince(startTime) * 1000
                    DebugLogger.shared.info("APP", "Apple Intelligence 완료: \(totalChars)자, \(Int(elapsed))ms")
                    DebugLogger.shared.perf("APP", "ai_response_time=\(Int(elapsed))ms chars=\(totalChars)")
                    continuation.finish()
                } catch is CancellationError {
                    DebugLogger.shared.warn("APP", "Apple Intelligence 요청 취소됨")
                    continuation.finish()
                } catch let error as AppError {
                    DebugLogger.shared.error("APP", "[\(error.errorCode)] \(error.localizedDescription ?? "")")
                    continuation.finish(throwing: error)
                } catch {
                    // 컨텍스트 초과는 원인이 명확하므로 사용자 행동 유도 메시지로 매핑 (v2.1 T-104)
                    let description = error.localizedDescription
                    if description.contains("context window") || description.contains("context") {
                        DebugLogger.shared.error("APP", "[E-MAC-AI-1004] 컨텍스트 초과: \(description)")
                        continuation.finish(throwing: AppError.unsupportedFeature(
                            "대화가 너무 길어 Apple Intelligence가 처리할 수 없습니다. 새 대화를 시작하거나 다른 모델을 선택해 주세요."
                        ))
                    } else {
                        DebugLogger.shared.error("APP", "[E-MAC-AI-1003] 응답 생성 실패: \(description)")
                        continuation.finish(throwing: AppError.unsupportedFeature("Apple Intelligence 응답 생성에 실패했습니다."))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Apple Intelligence 컨텍스트 예산(문자) — 온디바이스 모델 한계가 작아 초과 전 선제 절단 (v2.1 T-104)
    static let contextCharBudget = 12_000

    /// 대화 이력을 단일 프롬프트로 조합. 예산 초과 시 오래된 메시지부터 제외 (v2.0 T-79, 가드 v2.1 T-104)
    /// - Returns: (프롬프트, 제외된 메시지 수)
    static func buildTrimmedPrompt(from messages: [ChatMessage]) -> (prompt: String, dropped: Int) {
        var lines: [(String, Int)] = []
        for (index, message) in messages.enumerated() where message.role == .user || message.role == .assistant {
            let speaker = message.role == .user ? "사용자" : "어시스턴트"
            lines.append(("[\(speaker)] \(message.content)", index))
        }

        // 최근 메시지부터 역방향으로 누적해 예산 내에서 절단
        var kept: [(String, Int)] = []
        var total = 0
        for entry in lines.reversed() {
            total += entry.0.count + 2
            if total > contextCharBudget { break }
            kept.append(entry)
        }
        kept.reverse()

        let dropped = messages.count - kept.count
        if dropped > 0 {
            DebugLogger.shared.warn("APP", "[CONTEXT] Apple Intelligence 예산(\(contextCharBudget)자) 초과 — 오래된 \(dropped)개 메시지 제외")
        }
        return (kept.map(\.0).joined(separator: "\n\n"), max(0, dropped))
    }

    /// 하위 호환용 — 기존 시그니처 유지
    static func buildPrompt(from messages: [ChatMessage]) -> String {
        buildTrimmedPrompt(from: messages).prompt
    }
}
