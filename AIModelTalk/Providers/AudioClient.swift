import Foundation

/// TTS 합성 결과 (v0.3.3 T-332)
struct AudioSpeechResult {
    let text: String
    let audioData: Data
    let modelID: String
    let provider: Provider
}

/// 오디오 TTS 클라이언트 (v0.3.3 T-332) — NVIDIA NIM 호환 POST /audio/speech (JSON)
/// OpenAI 호환 스키마 {model, input, response_format: mp3} → 오디오 바이트.
/// Magpie 모델 ID·voice는 클라우드 실기동 미검증 — 404면 AppError.serverError로
/// 기존 410/404 자동제외(disableUnavailableModel)가 처리한다.
@MainActor
enum AudioClient {

    /// 음성 합성 — 텍스트를 지정 TTS 모델로 합성해 mp3 바이트 반환
    /// - Parameters:
    ///   - text: 합성할 텍스트 (최대 2000자, NIM 제한)
    ///   - model: ModelCatalog의 오디오 모델 (provider/audioModelID)
    static func speak(text: String, model: AIModel) async throws -> AudioSpeechResult {
        DebugLogger.shared.info("AUDIO", "[INFO] [FEATURE] <오디오 TTS> 합성 시작 — 모델 \(model.id)")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.network("합성할 텍스트가 비어 있습니다.")
        }
        // NIM은 최대 2000자 — 초과분은 잘라서 요청 (잘림은 로그에 명시)
        let input: String
        if trimmed.count > 2000 {
            input = String(trimmed.prefix(2000))
            DebugLogger.shared.warn("AUDIO", "텍스트 2000자 초과 — 앞 2000자만 합성")
        } else {
            input = trimmed
        }
        let key = AppSettings.shared.apiKey(for: model.provider)
        guard !key.isEmpty else {
            throw AppError.missingKey(model.provider)
        }
        let base = baseURL(for: model.provider).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/audio/speech") else {
            throw AppError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        // voice 생략 = 서버 기본값 (한국어 voice ID 미확인, 후속 과제)
        let body: [String: Any] = [
            "model": model.id,
            "input": input,
            "response_format": "mp3",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw AppError.cancelled
        } catch {
            throw AppError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AppError.network("응답 없음")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            DebugLogger.shared.error("AUDIO", "TTS 합성 실패 (HTTP \(http.statusCode)): \(detail)")
            throw AppError.serverError(http.statusCode, detail)
        }
        // 성공 응답은 오디오 바이트 (audio/mpeg 등). JSON 에러가 섞여 오면 파싱 실패 처리.
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard contentType.hasPrefix("audio/"), !data.isEmpty else {
            DebugLogger.shared.error("AUDIO", "TTS 응답에서 오디오 데이터를 찾지 못함 (Content-Type: \(contentType))")
            throw AppError.parseError
        }
        DebugLogger.shared.info("AUDIO", "[FEATURE] TTS 합성 완료 — \(data.count) bytes")
        return AudioSpeechResult(text: input, audioData: data, modelID: model.id, provider: model.provider)
    }

    /// 공급자별 오디오 엔드포인트 베이스 URL
    static func baseURL(for provider: Provider) -> String {
        if provider == .custom {
            let u = AppSettings.shared.customBaseURL.trimmingCharacters(in: .whitespaces)
            return u.isEmpty ? "https://localhost" : u
        }
        return provider.baseURL
    }
}
