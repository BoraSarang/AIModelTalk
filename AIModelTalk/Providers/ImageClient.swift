import Foundation

/// 이미지 생성 결과 (v0.3.x 축4)
struct ImageGenerationResult {
    let prompt: String
    let imageData: Data
    let modelID: String
    let provider: Provider
    let revisedPrompt: String?
}

/// 이미지 생성 클라이언트 (v0.3.x 축4) — OpenAI 호환 /v1/images/generations
/// OpenAI·OpenCode Zen·DeepSeek 등 OpenAI 호환 게이트웨이에서 동작.
@MainActor
enum ImageClient {

    struct ImageError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 공급자별 OpenAI 호환 API 키 조회
    static func apiKey(for provider: Provider) -> String? {
        let s = AppSettings.shared
        switch provider {
        case .openAI: return s.openAIAPIKey
        case .opencode: return s.opencodeAPIKey
        case .deepseek: return s.deepseekAPIKey
        case .custom: return s.customAPIKey
        default: return nil
        }
    }

    /// 공급자별 이미지 엔드포인트 베이스 URL (OpenAI 호환 gateway)
    static func baseURL(for provider: Provider) -> String {
        switch provider {
        case .custom:
            let u = AppSettings.shared.customBaseURL.trimmingCharacters(in: .whitespaces)
            return u.isEmpty ? "https://localhost" : u
        default:
            return provider.baseURL
        }
    }

    /// 이미지 생성 — 프롬프트를 지정 모델로 생성해 base64 이미지 반환
    /// - Parameters:
    ///   - prompt: 이미지 생성 프롬프트
    ///   - model: ModelCatalog의 이미지 모델 (provider/imageModelID)
    ///   - size: "1024x1024" 등
    static func generate(prompt: String, model: AIModel, size: String = "1024x1024") async throws -> ImageGenerationResult {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ImageError(message: "이미지 생성 프롬프트가 비어 있습니다.")
        }
        guard let key = apiKey(for: model.provider), !key.isEmpty else {
            throw ImageError(message: "\(model.provider.rawValue)의 API 키가 설정되지 않았습니다. 설정 → 공급자에서 키를 추가해 주세요.")
        }
        let base = baseURL(for: model.provider).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: base)!
            .appendingPathComponent("images")
            .appendingPathComponent("generations")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model.id,
            "prompt": prompt,
            "n": 1,
            "size": size,
            "response_format": "b64_json"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        DebugLogger.shared.info("IMAGE", "[FEATURE] 이미지 생성 시작 — 모델 \(model.id), 프롬프트 \(prompt.prefix(40))…")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = try? JSONDecoder().decode(ImageErrorMessage.self, from: data)
            let detail = msg?.error?.message ?? "HTTP 오류"
            DebugLogger.shared.error("IMAGE", "[E-MAC-IMG-1001] 이미지 생성 실패: \(detail)")
            throw ImageError(message: detail)
        }

        let decoded = try JSONDecoder().decode(ImageGenerationResponse.self, from: data)
        guard let item = decoded.data.first, let b64 = item.b64_json,
              let imageData = Data(base64Encoded: b64) else {
            DebugLogger.shared.error("IMAGE", "[E-MAC-IMG-1002] 응답에서 이미지 데이터를 찾지 못함")
            throw ImageError(message: "이미지 응답을 해석할 수 없습니다.")
        }
        DebugLogger.shared.info("IMAGE", "[FEATURE] 이미지 생성 완료 — \(imageData.count) bytes")
        return ImageGenerationResult(
            prompt: prompt,
            imageData: imageData,
            modelID: model.id,
            provider: model.provider,
            revisedPrompt: item.revisedPrompt
        )
    }
}

// MARK: - 응답 모델

private struct ImageGenerationResponse: Decodable {
    let data: [ImageDataItem]
}

private struct ImageDataItem: Decodable {
    let b64_json: String?
    let revisedPrompt: String?
}

private struct ImageErrorMessage: Decodable {
    struct ErrBox: Decodable { let message: String? }
    let error: ErrBox?
}
