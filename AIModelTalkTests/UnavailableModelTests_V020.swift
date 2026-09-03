import XCTest
@testable import AIModelTalk

/// v0.2.0 — 공급자 무관 EOL(410)/모델없음(404) 자동 비활성화 + 갱신 리포트 사유 상세 테스트
final class UnavailableModelTests_V020: XCTestCase {

    // MARK: - AppError 판별

    func testIsGoneOnlyMatches410() {
        XCTAssertTrue(AppError.serverError(410, "gone").isGone)
        XCTAssertFalse(AppError.serverError(404, "nf").isGone)
        XCTAssertFalse(AppError.serverError(402, "balance").isGone)
        XCTAssertFalse(AppError.network("x").isGone)
    }

    func testIsModelNotFoundOnlyMatches404() {
        XCTAssertTrue(AppError.serverError(404, "nf").isModelNotFound)
        XCTAssertFalse(AppError.serverError(410, "gone").isModelNotFound)
        XCTAssertFalse(AppError.timeout.isModelNotFound)
    }

    // MARK: - 실패 사유 힌트

    func testFailureHintMapsStatusCodes() {
        XCTAssertEqual(ComparisonService.failureHint(for: .serverError(410, "")), "모델이 사용 종료되었습니다")
        XCTAssertEqual(ComparisonService.failureHint(for: .serverError(404, "")), "모델을 찾을 수 없습니다")
        XCTAssertEqual(ComparisonService.failureHint(for: .serverError(402, "")), "API 잔액 부족")
        XCTAssertEqual(ComparisonService.failureHint(for: .serverError(400, "")), "요청 형식 오류")
        XCTAssertEqual(ComparisonService.failureHint(for: .serverError(200, "")), "")
        XCTAssertEqual(ComparisonService.failureHint(for: .network("x")), "")
    }

    // MARK: - 갱신 리포트 실패 사유

    func testRefreshFailureReasonMapsCodes() {
        XCTAssertEqual(CatalogRefreshReport.refreshFailureReason(401), "인증 실패 (API 키 확인)")
        XCTAssertEqual(CatalogRefreshReport.refreshFailureReason(404), "목록 엔드포인트 404 — URL/방식 오류 확인")
        XCTAssertEqual(CatalogRefreshReport.refreshFailureReason(500), "공급자 서버 오류 (HTTP 500)")
    }

    func testSummaryTextIncludesFailureReasons() {
        let results = [
            ProviderRefreshResult(provider: .nvidia, status: .ok, addedCount: 2, removedCount: 0),
            ProviderRefreshResult(provider: .ollama, status: .failed, errorMessage: "Ollama 서버 접속 실패"),
        ]
        let text = CatalogRefreshReport.summaryText(results)
        XCTAssertTrue(text.contains("추가 2개"))
        XCTAssertTrue(text.contains("Ollama"))
        XCTAssertTrue(text.contains("서버 접속 실패"))
    }

    func testSummaryTextSuccessOnly() {
        let results = [
            ProviderRefreshResult(provider: .groq, status: .ok),
            ProviderRefreshResult(provider: .gemini, status: .ok),
        ]
        let text = CatalogRefreshReport.summaryText(results)
        XCTAssertTrue(text.contains("성공"))
        XCTAssertTrue(text.contains("Groq"))
        XCTAssertTrue(text.contains("Gemini"))
    }

    // MARK: - 자동 비활성화

    func testDisableUnavailableModelOn410() {
        let catalog = ModelCatalog.shared
        let model = AIModel(id: "v020-test-eol-410", provider: .nvidia, displayName: "EOL 테스트")
        catalog.setEnabled(model, true)
        defer { catalog.setEnabled(model, true) } // 상태 복원 (다른 테스트 오염 방지)

        let disabled = catalog.disableUnavailableModel(error: AppError.serverError(410, "gone"), model: model)

        XCTAssertTrue(disabled)
        XCTAssertFalse(catalog.isEnabled(model))
    }

    func testDisableUnavailableModelOn404() {
        let catalog = ModelCatalog.shared
        let model = AIModel(id: "v020-test-nf-404", provider: .gemini, displayName: "NF 테스트")
        catalog.setEnabled(model, true)
        defer { catalog.setEnabled(model, true) }

        let disabled = catalog.disableUnavailableModel(error: AppError.serverError(404, "nf"), model: model)

        XCTAssertTrue(disabled)
        XCTAssertFalse(catalog.isEnabled(model))
    }

    func testDisableUnavailableModelIgnoresNonGoneErrors() {
        let catalog = ModelCatalog.shared
        let model = AIModel(id: "v020-test-ok-200", provider: .openRouter, displayName: "OK 테스트")
        catalog.setEnabled(model, true)
        defer { catalog.setEnabled(model, true) }

        // 402(잔액)는 자동 비활성화하지 않음
        let disabled = catalog.disableUnavailableModel(error: AppError.serverError(402, "balance"), model: model)

        XCTAssertFalse(disabled)
        XCTAssertTrue(catalog.isEnabled(model))
    }
}