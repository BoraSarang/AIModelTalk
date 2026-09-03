import XCTest
@testable import AIModelTalk

// MARK: - v2.5 T-123: 아티팩트 프리뷰 — 코드펜스 감지·문서 생성

final class ArtifactPreviewTestsV123: XCTestCase {

    // MARK: - 언어 정규화

    func testNormalizedLanguageAliases() {
        XCTAssertEqual(ArtifactPreview.normalizedLanguage("HTML"), "html")
        XCTAssertEqual(ArtifactPreview.normalizedLanguage("htm"), "html")
        XCTAssertEqual(ArtifactPreview.normalizedLanguage("XHTML"), "html")
        XCTAssertEqual(ArtifactPreview.normalizedLanguage("svg"), "svg")
        XCTAssertEqual(ArtifactPreview.normalizedLanguage("mermaid"), "mermaid")
    }

    func testUnsupportedLanguagesReturnNil() {
        XCTAssertNil(ArtifactPreview.normalizedLanguage("swift"))
        XCTAssertNil(ArtifactPreview.normalizedLanguage(""))
        // 정보 문자열 추가 파라미터 — 첫 단어만 사용
        XCTAssertNil(ArtifactPreview.normalizedLanguage("js live"))
        XCTAssertEqual(ArtifactPreview.normalizedLanguage("mermaid theme=dark"), "mermaid")
    }

    // MARK: - 펜스 감지

    func testDetectsSingleHTMLBlock() {
        let md = """
        앞 문단입니다.

        ```html
        <p>hello</p>
        ```

        뒷 문단.
        """
        let blocks = ArtifactPreview.detectBlocks(in: md)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "html")
        XCTAssertTrue(blocks[0].code.contains("<p>hello</p>"))
    }

    func testDetectsMultipleBlocksInOrder() {
        let md = """
        ```svg
        <svg/>
        ```
        중간 텍스트
        ```mermaid
        graph TD; A-->B;
        ```
        """
        let blocks = ArtifactPreview.detectBlocks(in: md)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].language, "svg")
        XCTAssertEqual(blocks[1].language, "mermaid")
        XCTAssertEqual(blocks[1].code, "graph TD; A-->B;")
    }

    func testIgnoresUnsupportedFenceContent() {
        let md = """
        ```swift
        let x = 1
        ```
        ```html
        <b>ok</b>
        ```
        """
        let blocks = ArtifactPreview.detectBlocks(in: md)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "html")
    }

    func testSkippedFenceDoesNotSwallowFollowingBlock() {
        // 미지원 펜스가 닫힌 뒤 지원 블록이 정상 감지되어야 함
        let md = """
        ~~~python
        print('hi')
        ~~~
        ```html
        <i>x</i>
        ```
        """
        let blocks = ArtifactPreview.detectBlocks(in: md)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "html")
    }

    func testUnclosedBlockCollectsToEnd() {
        let md = "```html\n<p>truncated"
        let blocks = ArtifactPreview.detectBlocks(in: md)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].code, "<p>truncated")
    }

    func testIndentedFenceUpToThreeSpaces() {
        let md = "   ```html\n   <p>x</p>\n   ```\n끝"
        let blocks = ArtifactPreview.detectBlocks(in: md)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].code, "   <p>x</p>")
    }

    func testInlineBackticksDoNotOpenFence() {
        let md = "이것은 `inline code`이고 ```아닙니다```.\n\n```svg\n<svg width=\"1\"/>\n```"
        let blocks = ArtifactPreview.detectBlocks(in: md)
        // ```아닙니다```는 정보 문자열이 있어 미지원 펜스로 스킵되고 svg만 감지
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "svg")
    }

    // MARK: - 미리보기 문서

    func testMermaidDocumentWrapsCDNAndCode() {
        let doc = ArtifactPreview.previewDocument(language: "mermaid", code: "graph TD; A-->B;")
        XCTAssertTrue(doc.contains("cdn.jsdelivr.net/npm/mermaid"))
        XCTAssertTrue(doc.contains("graph TD; A--&gt;B;"))
        XCTAssertFalse(doc.contains("</script><script")) // 이중 스크립트 주입 아님
    }

    func testHTMLDocumentContainsCodeVerbatim() {
        let doc = ArtifactPreview.previewDocument(language: "html", code: "<h1>제목</h1>")
        XCTAssertTrue(doc.contains("<h1>제목</h1>"))
    }

    func testSVGDocumentCentersContent() {
        let doc = ArtifactPreview.previewDocument(language: "svg", code: "<svg viewBox=\"0 0 2 2\"></svg>")
        XCTAssertTrue(doc.contains("<svg viewBox=\"0 0 2 2\"></svg>"))
        XCTAssertTrue(doc.contains("display:flex"))
    }

    // MARK: - 저장 파일명·주입 페이로드

    func testSuggestedFileNames() {
        XCTAssertEqual(ArtifactPreview.suggestedFileName(index: 0, language: "html"), "artifact-1.html")
        XCTAssertEqual(ArtifactPreview.suggestedFileName(index: 2, language: "svg"), "artifact-3.svg")
        XCTAssertEqual(ArtifactPreview.suggestedFileName(index: 1, language: "mermaid"), "artifact-2.mmd")
    }

    func testInjectionPayloadEscapesClosingTags() {
        let blocks = [ArtifactPreview.Block(language: "html", code: "</script><script>alert(1)</script>")]
        let text = ArtifactPreview.injectionPayloadText(for: blocks, appearance: "light")
        XCTAssertFalse(text.contains("</script>"))
        XCTAssertTrue(text.contains("<\\/script>"))
    }
}
