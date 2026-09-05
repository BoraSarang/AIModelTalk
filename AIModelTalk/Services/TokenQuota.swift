import Foundation
import SwiftUI

/// 공급자 계정이 응답 헤더로 보고하는 토큰 쿼터 (v0.3.2)
/// — Anthropic이 `x-ratelimit-limit/remaining/usage-tokens` 제공. 마지막 응답 기준.
struct ProviderAccountQuota: Equatable {
    let provider: Provider
    let limit: Int
    let remaining: Int
    let used: Int
    let updatedAt: Date

    var ratio: Double { limit > 0 ? Double(used) / Double(limit) : 0 }
}

/// 선택 모델 기준 토큰 상태 스냅샷 (v0.3.2)
struct ModelTokenSnapshot: Equatable {
    let model: AIModel
    /// 이 모델(provider+modelID 일치)로 응답받은 메시지들의 실측 usage 누적
    let measuredPrompt: Int
    let measuredCompletion: Int
    /// 표시용 사용량 — 실측 있으면 실측 합, 없으면 추정 (source로 구분)
    let used: Int
    let limit: Int
    let source: TokenSource
    let estimated: Int

    enum TokenSource: Equatable {
        case measured
        case estimated
    }

    var measuredTotal: Int { measuredPrompt + measuredCompletion }
    var remaining: Int { max(0, limit - used) }
    var ratio: Double { limit > 0 ? Double(used) / Double(limit) : 0 }
    var isOverLimit: Bool { used > limit }
    var hasLimit: Bool { limit > 0 }
}

/// 토큰 상태 계산 + 공급자 계정 쿼터 보관 (v0.3.2)
@MainActor
final class TokenQuotaStore: ObservableObject {
    static let shared = TokenQuotaStore()

    /// 공급자별 계정 쿼터 (Anthropic 헤더 등) — 마지막 응답 기준 유지
    @Published private(set) var accountQuotas: [Provider: ProviderAccountQuota] = [:]

    private init() {}

    // MARK: - 헤더 캡처 (공급자 계정 풀)

    /// HTTP 응답 헤더에서 공급자별 토큰 쿼터 추출. 현재는 Anthropic 지원.
    /// 비동기 요청 처리 스레드에서 안전하게 호출되도록 nonisolated.
    static nonisolated func capture(headers: [AnyHashable: Any], provider: Provider) {
        switch provider {
        case .anthropic:
            var map: [String: Any] = [:]
            for (key, value) in headers {
                if let keyString = key as? String {
                    map[keyString.lowercased()] = value
                }
            }
            guard let limit = headerInt(map["x-ratelimit-limit-tokens"]),
                  let remaining = headerInt(map["x-ratelimit-remaining-tokens"]) else {
                return
            }
            let used = headerInt(map["x-ratelimit-usage-tokens"]) ?? max(0, limit - remaining)
            let quota = ProviderAccountQuota(
                provider: provider,
                limit: limit,
                remaining: remaining,
                used: used,
                updatedAt: Date()
            )
            Task { @MainActor in
                shared.accountQuotas[provider] = quota
            }
            DebugLogger.shared.info("TOKEN", "[ACCOUNT] \(provider.rawValue) 쿼터 캡처: 남음 \(remaining)/\(limit) 토큰")
        default:
            break
        }
    }

    private static nonisolated func headerInt(_ value: Any?) -> Int? {
        guard let string = value as? String, let number = Int(string) else { return nil }
        return number
    }

    // MARK: - 스냅샷 (모델 컨텍스트 풀)

    /// 현재 세션에서 선택 모델과 동일(provider+modelID) 메시지의 실측 누적 기준 상태.
    /// 실측이 한 번도 없으면 추정 폴백. (v0.3.2)
    static func snapshot(model: AIModel, messages: [ChatMessage], systemPrompt: String) -> ModelTokenSnapshot {
        let matched = messages.filter { $0.provider == model.provider && $0.modelID == model.id }
        let prompt = matched.compactMap(\.promptTokens).reduce(0, +)
        let completion = matched.compactMap(\.completionTokens).reduce(0, +)
        if prompt + completion > 0 {
            return ModelTokenSnapshot(
                model: model,
                measuredPrompt: prompt,
                measuredCompletion: completion,
                used: prompt + completion,
                limit: model.contextLimit,
                source: .measured,
                estimated: 0
            )
        }
        let estimated = TokenEstimator.estimateConversation(systemPrompt: systemPrompt, messages: messages)
        return ModelTokenSnapshot(
            model: model,
            measuredPrompt: 0,
            measuredCompletion: 0,
            used: estimated,
            limit: model.contextLimit,
            source: .estimated,
            estimated: estimated
        )
    }

    // MARK: - 포맷

    static func compact(_ number: Int) -> String {
        SessionTokens.compact(number)
    }

    static func thousands(_ number: Int) -> String {
        number >= 1000 ? String(format: "%.1fK", Double(number) / 1000) : "\(number)"
    }
}