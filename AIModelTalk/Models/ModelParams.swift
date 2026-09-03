import Foundation

/// 모델 실행 파라미터 — 세션/래인별 샘플링 옵션 (v0.2.0 T-202)
/// 모든 값이 nil이면 각 공급자 기본값을 사용한다.
struct ModelParams: Equatable, Codable {
    /// 캐릭터별 샘플링 온도 — nil이면 공급자 기본값
    var temperature: Double?
    /// top-p(nucleus sampling) — nil이면 공급자 기본값
    var topP: Double?
    /// 최대 출력 토큰 — nil이면 공급자 기본값
    var maxTokens: Int?

    static let none = ModelParams(temperature: nil, topP: nil, maxTokens: nil)

    /// 하나라도 설정됐는지 — 전부 nil이면 공급자 기본값만 사용
    var hasAny: Bool { temperature != nil || topP != nil || maxTokens != nil }
}