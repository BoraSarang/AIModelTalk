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

    // MARK: - 상태코드별 안내 문구 (errorDescription)

    func testErrorDescriptionMapsStatusCodes() {
        XCTAssertEqual(AppError.serverError(410, "").localizedDescription, "모델이 사용 종료(EOL)되어 목록에서 자동 제외됩니다. (HTTP 410)")
        XCTAssertEqual(AppError.serverError(404, "").localizedDescription, "모델을 찾을 수 없습니다. 모델/공급자 설정을 확인해 주세요. (HTTP 404)")
        XCTAssertEqual(AppError.serverError(402, "").localizedDescription, "API 잔액이 부족합니다. 충전 후 다시 시도해 주세요. (HTTP 402)")
        XCTAssertEqual(AppError.serverError(400, "").localizedDescription, "요청 형식이 올바르지 않습니다. 내용을 확인한 후 다시 시도해 주세요.")
        XCTAssertTrue(AppError.serverError(401, "").localizedDescription.contains("인증에 실패했습니다"))
        XCTAssertTrue(AppError.serverError(429, "").localizedDescription.contains("사용 한도를 초과했습니다"))
        XCTAssertTrue(AppError.serverError(503, "").localizedDescription.contains("공급자 서버에 오류가 발생했습니다"))
        XCTAssertTrue(AppError.network("x").localizedDescription.contains("네트워크 오류"))
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

    // MARK: - 자동 정리 기록(autoDisabled)

    func testAutoDisabledRecordedOn410() {
        let catalog = ModelCatalog.shared
        let model = AIModel(id: "v020-auto-410", provider: .nvidia, displayName: "자동정리 410")
        let key = "\(Provider.nvidia.rawValue):v020-auto-410"
        catalog.setEnabled(model, true)
        defer { catalog.setEnabled(model, true) }

        _ = catalog.disableUnavailableModel(error: AppError.serverError(410, "gone"), model: model)

        XCTAssertTrue(catalog.autoDisabledKeys.contains(key))
        XCTAssertEqual(catalog.autoDisabledCount, catalog.autoDisabledKeys.count)
    }

    func testAutoDisabledNotRecordedOnManualDisable() {
        let catalog = ModelCatalog.shared
        let model = AIModel(id: "v020-manual-off", provider: .gemini, displayName: "수동 해제")
        let key = "\(Provider.gemini.rawValue):v020-manual-off"
        catalog.setEnabled(model, true)
        defer { catalog.setEnabled(model, true) }

        catalog.setEnabled(model, false) // 수동 해제 — 자동 정리 아님

        XCTAssertFalse(catalog.autoDisabledKeys.contains(key))
    }

    func testReEnablingClearsAutoDisabled() {
        let catalog = ModelCatalog.shared
        let model = AIModel(id: "v020-reenable", provider: .groq, displayName: "재활성화")
        let key = "\(Provider.groq.rawValue):v020-reenable"
        defer { catalog.setEnabled(model, true) }

        _ = catalog.disableUnavailableModel(error: AppError.serverError(410, "gone"), model: model)
        XCTAssertTrue(catalog.autoDisabledKeys.contains(key))

        catalog.setEnabled(model, true)
        XCTAssertFalse(catalog.autoDisabledKeys.contains(key))
    }
}