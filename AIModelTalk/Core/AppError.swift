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

    /// 모델 EOL(410 Gone) — 명확한 모델 사용 종료. 공급자 무관 자동 비활성화 대상.
    var isGone: Bool {
        if case .serverError(let code, _) = self { return code == 410 }
        return false
    }

    /// 모델 없음(404 Not Found) — 채팅/비교/판정 호출부에서만 모델 문제로 판정.
    /// (모델 목록 조회에서의 404는 호출 방식/URL 오류일 수 있어 별도 구분)
    var isModelNotFound: Bool {
        if case .serverError(let code, _) = self { return code == 404 }
        return false
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
            // HTTP 상태코드별 원인을 사용자 언어로 명확히 안내 (v0.2.0)
            switch code {
            case 400:
                return "요청 형식이 올바르지 않습니다. 내용을 확인한 후 다시 시도해 주세요."
            case 401, 403:
                return "인증에 실패했습니다. 설정에서 API 키를 확인해 주세요. (HTTP \(code))"
            case 402:
                return "API 잔액이 부족합니다. 충전 후 다시 시도해 주세요. (HTTP 402)"
            case 404:
                return "모델을 찾을 수 없습니다. 모델/공급자 설정을 확인해 주세요. (HTTP 404)"
            case 410:
                return "모델이 사용 종료(EOL)되어 목록에서 자동 제외됩니다. (HTTP 410)"
            case 429:
                return "요청이 너무 많거나 무료 사용 한도를 초과했습니다. 잠시 후 다시 시도해 주세요. (HTTP 429)"
            case 500..<600:
                return "공급자 서버에 오류가 발생했습니다. 잠시 후 다시 시도해 주세요. (HTTP \(code))"
            default:
                return "서버에서 오류를 반환했습니다. (HTTP \(code))"
            }
        case .parseError:
            return "스트리밍 응답을 파싱하지 못했습니다."
        case .cancelled:
            return nil
        case .unsupportedFeature(let feature):
            return "\(feature)"
        }
    }
}