import XCTest
@testable import AIModelTalk

// MARK: - v2.5 T-124: React(JSX) 프리뷰 스파이크 — 감지·문서 생성·파일명

final class ArtifactReactSpikeTestsV124: XCTestCase {

    func testNormalizedLanguageReactAndJsx() {
        XCTAssertEqual(ArtifactPreview.normalizedLanguage("react"), "react")
        XCTAssertEqual(ArtifactPreview.normalizedLanguage("jsx"), "react")
        XCTAssertEqual(ArtifactPreview.normalizedLanguage("JSX"), "react")
        XCTAssertTrue(ArtifactPreview.supportedLanguages.contains("react"))
    }

    func testDetectBlocksFindsReactFence() {
        let md = """
        앞 설명

        ```jsx
        const App = () => <h1>안녕</h1>;
        ```
        """
        let blocks = ArtifactPreview.detectBlocks(in: md)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "react")
        XCTAssertTrue(blocks[0].code.contains("const App"))
    }

    func testReactDocumentIncludesCDNsAndRootDiv() {
        let doc = ArtifactPreview.previewDocument(language: "react", code: "<div/>")
        XCTAssertTrue(doc.contains("cdn.jsdelivr.net/npm/react@18"))
        XCTAssertTrue(doc.contains("react-dom@18"))
        XCTAssertTrue(doc.contains("@babel/standalone/babel.min.js"))
        XCTAssertTrue(doc.contains(#"<script type="text/babel">"#))
        XCTAssertTrue(doc.contains(#"<div id="root"></div>"#))
        // 실패 시 빈 화면 대신 오류 표시 + App 자동 렌더 폴백
        XCTAssertTrue(doc.contains("addEventListener('error'"))
        XCTAssertTrue(doc.contains("createRoot(r).render(React.createElement(App))"))
        // 외부 스크립트 태그는 JSON 직렬화 시 이스케이프되므로 문서 자체는 원문 유지
        XCTAssertTrue(doc.contains("</script>"))
    }

    func testReactFileNameUsesJsxExtension() {
        XCTAssertEqual(ArtifactPreview.suggestedFileName(index: 2, language: "react"), "artifact-3.jsx")
    }
}
