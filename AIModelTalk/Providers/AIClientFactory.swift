import Foundation

@MainActor
enum AIClientFactory {
    static func client(provider: Provider, modelID: String) throws -> ChatClient {
        DebugLogger.shared.info("API", "클라이언트 생성: 공급자=\(provider.rawValue), 모델=\(modelID)")

        if provider == .ollama {
            let baseURL = AppSettings.shared.ollamaBaseURL.isEmpty ? provider.baseURL : AppSettings.shared.ollamaBaseURL
            let client = OllamaClient(baseURL: baseURL, model: modelID)
            DebugLogger.shared.info("API", "OllamaClient 생성 완료")
            return client
        }

        if provider == .appleIntelligence {
            guard AppleIntelligenceSupport.osSupported else {
                DebugLogger.shared.error("API", "[E-MAC-AI-1001] Apple Intelligence OS 미지원")
                throw AppError.unsupportedFeature("Apple Intelligence는 macOS 26 이상에서 사용할 수 있습니다.")
            }
            DebugLogger.shared.info("API", "[FEATURE] AppleIntelligenceClient 선택됨")
            return AppleIntelligenceClient()
        }

        // 커스텀은 엔드포인트 목록에서 라우팅 — 키 없는 로컬 서버(LM Studio 등) 허용 (v1.9 T-84)
        if provider == .custom {
            let store = CustomEndpointStore(defaults: CustomEndpointStore.suiteDefaults)
            var endpointID: UUID? = nil
            var rawModelID = modelID
            if let parsed = CustomEndpoint.parse(modelID) {
                endpointID = parsed.endpointID
                rawModelID = parsed.rawModelID
            }
            let endpoint = endpointID.flatMap { id in store.endpoints.first { $0.id == id } }
                ?? store.endpoints.first // 프리픽스 없는 구형 모델 → 첫 엔드포인트 폴백

            guard let ep = endpoint else {
                DebugLogger.shared.error("API", "[E-MAC-CUST-1001] 커스텀 엔드포인트 미등록 (modelID: \(modelID.prefix(60)))")
                throw AppError.missingKey(.custom)
            }
            guard !ep.baseURL.isEmpty else {
                DebugLogger.shared.error("API", "[E-MAC-CUST-1002] 엔드포인트 '\(ep.name)' BaseURL 비어 있음")
                throw AppError.missingKey(.custom)
            }
            DebugLogger.shared.info("API", "CustomClient 생성: '\(ep.name)' (\(ep.baseURL)) 모델=\(rawModelID), 키 \(ep.apiKey.isEmpty ? "없음" : "있음")")
            return OpenAICompatibleClient(provider: .custom, apiKey: ep.apiKey, baseURL: ep.baseURL, model: rawModelID)
        }

        let key = AppSettings.shared.apiKey(for: provider)
        if key.isEmpty {
            DebugLogger.shared.error("API", "[E-MAC-KEY-1001] \(provider.rawValue) API 키 없음")
        }
        guard !key.isEmpty else {
            throw AppError.missingKey(provider)
        }
        DebugLogger.shared.debug("API", "API 키 확인 완료 (길이: \(key.count)자)")

        if provider == .gemini {
            let client = GeminiClient(apiKey: key, model: modelID)
            DebugLogger.shared.info("API", "GeminiClient 생성 완료")
            return client
        }

        if provider == .anthropic {
            DebugLogger.shared.info("API", "[FEATURE] AnthropicClient 생성 완료 (모델: \(modelID))")
            return AnthropicClient(apiKey: key, model: modelID)
        }

        let baseURL = provider.baseURL
        DebugLogger.shared.debug("API", "BaseURL: \(baseURL)")
        let client = OpenAICompatibleClient(provider: provider, apiKey: key, baseURL: baseURL, model: Provider.wireModelID(modelID, for: provider))
        DebugLogger.shared.info("API", "OpenAICompatibleClient 생성 완료 (전송 모델: \(Provider.wireModelID(modelID, for: provider)))")
        return client
    }
}