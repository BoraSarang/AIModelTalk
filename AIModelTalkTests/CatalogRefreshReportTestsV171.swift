import XCTest
@testable import AIModelTalk

/// v1.7.1 갱신 리포트 요약 문구 테스트 (T-58)
final class CatalogRefreshReportTestsV171: XCTestCase {

    private func result(
        _ provider: Provider,
        _ status: ProviderRefreshResult.Status,
        added: Int = 0,
        removed: Int = 0
    ) -> ProviderRefreshResult {
        ProviderRefreshResult(provider: provider, status: status, addedCount: added, removedCount: removed)
    }

    func testAllSkippedShowsKeyHint() {
        let text = CatalogRefreshReport.summaryText([
            result(.openRouter, .skipped),
            result(.gemini, .skipped),
        ])
        XCTAssertEqual(text, "API 키가 설정된 공급자가 없습니다")
    }

    func testNoChanges() {
        let text = CatalogRefreshReport.summaryText([
            result(.groq, .ok),
            result(.nvidia, .ok),
        ])
        XCTAssertEqual(text, "변경 없음 (Groq, NVIDIA)")
    }

    func testAddedAndRemoved() {
        let text = CatalogRefreshReport.summaryText([
            result(.openRouter, .ok, added: 3, removed: 1),
            result(.groq, .ok),
        ])
        XCTAssertEqual(text, "추가 3개, 제거 1개 (OpenRouter, Groq)")
    }

    func testPartialFailureListed() {
        let text = CatalogRefreshReport.summaryText([
            result(.openRouter, .ok, added: 2),
            result(.groq, .failed),
        ])
        XCTAssertEqual(text, "추가 2개 (OpenRouter) / 실패: Groq")
    }
}
