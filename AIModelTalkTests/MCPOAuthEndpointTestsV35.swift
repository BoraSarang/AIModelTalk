import XCTest
@testable import AIModelTalk

/// v0.3.3 — 수동 OAuth 엔드포인트 결정 테스트 (T-333)
/// 커스텀 입력 > 템플릿 내장값 > nil 우선순위 검증
final class MCPOAuthEndpointTestsV35: XCTestCase {

    private var gitlab: MCPProviderTemplate {
        MCPProviderTemplate.catalog.first { $0.id == "gitlab" }!
    }

    private var vercel: MCPProviderTemplate {
        MCPProviderTemplate.catalog.first { $0.id == "vercel" }!
    }

    /// 커스텀 입력이 템플릿보다 우선
    func testCustomOverridesTemplate() {
        let r = MCPOAuthService.resolveEndpoints(
            template: gitlab,
            customAuthorizationEndpoint: "https://gitlab.example.com/oauth/authorize",
            customTokenEndpoint: "https://gitlab.example.com/oauth/token"
        )
        XCTAssertEqual(r.authorizationEndpoint, "https://gitlab.example.com/oauth/authorize")
        XCTAssertEqual(r.tokenEndpoint, "https://gitlab.example.com/oauth/token")
    }

    /// 빈 입력은 템플릿 내장값으로 폴백 (GitLab 대조값 확인)
    func testBlankFallsBackToTemplate() {
        let r = MCPOAuthService.resolveEndpoints(
            template: gitlab,
            customAuthorizationEndpoint: "  ",
            customTokenEndpoint: nil
        )
        XCTAssertEqual(r.authorizationEndpoint, "https://gitlab.com/oauth/authorize")
        XCTAssertEqual(r.tokenEndpoint, "https://gitlab.com/oauth/token")
    }

    /// 둘 다 없으면 nil (수동 연결 불가 판정에 사용)
    func testBothMissingReturnsNil() {
        let r = MCPOAuthService.resolveEndpoints(
            template: vercel,
            customAuthorizationEndpoint: nil,
            customTokenEndpoint: ""
        )
        XCTAssertNil(r.authorizationEndpoint)
        XCTAssertNil(r.tokenEndpoint)
    }

    /// Slack 템플릿 내장값 대조
    func testSlackTemplateEndpoints() {
        let slack = MCPProviderTemplate.catalog.first { $0.id == "slack" }!
        XCTAssertEqual(slack.authorizationEndpoint, "https://slack.com/oauth/v2/authorize")
        XCTAssertEqual(slack.tokenEndpoint, "https://slack.com/api/oauth.v2.access")
    }
}
