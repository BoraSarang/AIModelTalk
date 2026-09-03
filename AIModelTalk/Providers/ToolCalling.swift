import Foundation

/// 도구 정의 — LLM 요청 바디용 (v2.4 T-120)
/// MCPTool에서 변환되어 클라이언트에 전달된다
struct LLMToolDefinition: Hashable {
    let name: String
    let description: String
    /// JSON Schema 원본 문자열
    let parametersJSON: String
}

/// 모델이 요청한 도구 호출 (v2.4 T-120)
struct LLMToolCall: Equatable {
    let id: String
    let name: String
    /// JSON 인자 문자열 — 파싱 실패 시 빈 객체로 폴백
    let argumentsJSON: String
}

/// 도구 지원 스트리밍 이벤트 — 텍스트 델타 또는 도구 호출 묶음
enum ChatStreamEvent {
    case text(String)
    case toolCalls([LLMToolCall])
}

// MARK: - ChatClient 도구 확장

extension ChatClient {

    /// 도구 호출 미지원 기본값 — OpenAI 호환·Anthropic만 재정의 (v2.4 T-120)
    var supportsTools: Bool { false }

    /// 실제 도구 스트림 기본 구현 — 미지원 오류로 즉시 종료
    func rawStreamWithTools(
        messages: [ChatMessage], systemPrompt: String?, temperature: Double?,
        tools: [LLMToolDefinition], onUsage: ((Int?, Int?) -> Void)?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: AppError.network("도구 호출 미지원 클라이언트"))
        }
    }

    /// 도구 포함 스트리밍 — 도구 목록이 비면 기존 텍스트 스트림으로 위임,
    /// 도구가 있는데 미지원 클라이언트면 오류로 종료(호출부가 폴백 판단).
    /// supportsTools·rawStreamWithTools는 프로토콜 요구사항이라 동적 디스패치된다.
    func streamWithTools(
        messages: [ChatMessage],
        systemPrompt: String?,
        temperature: Double?,
        tools: [LLMToolDefinition],
        onUsage: ((Int?, Int?) -> Void)?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        if tools.isEmpty {
            let base = stream(messages: messages, systemPrompt: systemPrompt, temperature: temperature, onUsage: onUsage)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await chunk in base {
                            continuation.yield(.text(chunk))
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        guard supportsTools else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AppError.network("이 모델은 도구 호출을 지원하지 않습니다"))
            }
        }
        return rawStreamWithTools(messages: messages, systemPrompt: systemPrompt, temperature: temperature, tools: tools, onUsage: onUsage)
    }
}
