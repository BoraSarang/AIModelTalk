import Foundation

/// 공통 OAuth 에러 타입
enum OAuthError: Error, LocalizedError {
    case timeout
    case invalidCallback
    case missingCode
    case missingState
    case stateMismatch
    case serverError(String)
    case tokenExchangeFailed(String)
    case noRegistrationEndpoint
    case invalidLoopbackPort
    case missingClientCredentials

    var errorDescription: String? {
        switch self {
        case .timeout: return "OAuth 콜백 타임아웃 (5분)"
        case .invalidCallback: return "잘못된 콜백 요청"
        case .missingCode: return "인증 코드 누락"
        case .missingState: return "state 파라미터 누락"
        case .stateMismatch: return "state 불일치 — CSRF 공격 가능성"
        case .serverError(let msg): return msg
        case .tokenExchangeFailed(let msg): return "토큰 교환 실패: \(msg)"
        case .noRegistrationEndpoint: return "DCR 엔드포인트 없음"
        case .invalidLoopbackPort: return "루프백 포트 바인딩 실패"
        case .missingClientCredentials: return "Client ID/Secret을 입력하세요"
        }
    }
}