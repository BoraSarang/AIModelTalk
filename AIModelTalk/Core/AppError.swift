import Foundation

enum AppError: Error, LocalizedError {
    case missingKey(Provider)
    case invalidURL
    case network(String)
    case timeout
    case serverError(Int, String)
    case parseError
    case cancelled
    case unsupportedFeature(String)

    var errorCode: String {
        switch self {
        case .missingKey: return "E-MAC-KEY-1001"
        case .invalidURL: return "E-MAC-API-1001"
        case .network: return "E-MAC-NET-1001"
        case .timeout: return "E-MAC-NET-1002"
        case .serverError(let code, _):
            // 429(무료 티어 요청 한도/속도 초과)는 별도 코드로 구분 (v3.2 T-154)
            if code == 429 { return "E-MAC-NET-1005" }
            return "E-MAC-API-1001"
        case .parseError: return "E-MAC-API-1002"
        case .cancelled: return ""
        case .unsupportedFeature: return "E-MAC-API-1003"
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider):
            return "\(provider.rawValue) API 키가 없습니다. 설정에서 입력해 주세요."
        case .invalidURL:
            return "URL이 유효하지 않습니다."
        case .network(let msg):
            return "네트워크 오류가 발생했습니다. (\(msg))"
        case .timeout:
            return "요청 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요."
        case .serverError(let code, _):
            // 429: 공급자(특히 무료 티어) 요청 한도/속도 초과 — 재시도 안내 메시지 (v3.2 T-154)
            if code == 429 {
                return "요청이 너무 많거나 무료 사용 한도를 초과했습니다. 잠시 후 다시 시도해 주세요. (HTTP 429)"
            }
            return "서버에서 오류를 반환했습니다. (HTTP \(code))"
        case .parseError:
            return "스트리밍 응답을 파싱하지 못했습니다."
        case .cancelled:
            return nil
        case .unsupportedFeature(let feature):
            return "\(feature)"
        }
    }
}