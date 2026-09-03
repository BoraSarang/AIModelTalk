import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - WKWebView 서브클래스: 스크롤 이벤트를 상위 뷰에 전달

class NoScrollWKWebView: WKWebView {
    /// 고정 높이 모드에서 true — 세로 휠을 웹뷰 내부 스크롤로 소비하고 상위로 포워딩하지 않음 (v1.9 T-89)
    var allowsInternalVerticalScroll = false

    override func scrollWheel(with event: NSEvent) {
        // 가로 스크롤은 항상 웹뷰 내부 처리 (코드블록 가로 스크롤)
        guard abs(event.deltaY) >= abs(event.deltaX) else {
            super.scrollWheel(with: event)
            return
        }
        if allowsInternalVerticalScroll {
            // 웹 문서 자체가 스크롤 영역인 모드 — 네이티브 내부 스크롤 사용
            super.scrollWheel(with: event)
            return
        }
        // 세로 스크롤만 상위 뷰로 포워딩 (높이 피팅 모드 기본 동작)
        var responder: NSResponder? = self.nextResponder
        while let current = responder {
            if let scrollView = current as? NSScrollView {
                scrollView.scrollWheel(with: event)
                return
            }
            responder = current.nextResponder
        }
        self.superview?.scrollWheel(with: event)
    }
    /// 웹뷰 HTML의 oncontextmenu 억제를 우회 — 우클릭을 상위로 전달해
    /// SwiftUI contextMenu가 뜰 수 있도록 한다 (v2.1 말풍선 분기 접근성)
    override func rightMouseDown(with event: NSEvent) {
        superview?.rightMouseDown(with: event)
    }

    override var isFlipped: Bool { true }
}

/// WKWebView 기반 마크다운 렌더러 (스트리밍 지원)
struct MarkdownRenderer: View {
    let text: String
    var isStreaming: Bool = false
    /// 고정 높이 모드 — 높이를 제한하고 웹 문서 자체 스크롤 사용 (v1.9 T-89 비교 카드)
    /// nil이면 기존 방식: 콘텐츠 높이에 맞춰 성장, 외부 스크롤이 담당
    var fixedHeight: CGFloat? = nil
    @ObservedObject private var settings = AppSettings.shared
    @State private var contentHeight: CGFloat = 20

    var body: some View {
        if let fixedHeight {
            MarkdownWebView(
                text: text,
                isStreaming: isStreaming,
                appearance: settings.appearance,
                contentHeight: .constant(fixedHeight),
                scrollsInternally: true
            )
            .frame(height: fixedHeight)
            .clipped()
        } else {
            MarkdownWebView(
                text: text,
                isStreaming: isStreaming,
                appearance: settings.appearance,
                contentHeight: $contentHeight,
                scrollsInternally: false
            )
            .frame(height: contentHeight)
        }
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let isStreaming: Bool
    let appearance: String
    @Binding var contentHeight: CGFloat
    /// 웹 문서 자체 스크롤 모드 — 고정 높이 + CSS overflow-y auto (v1.9 T-89)
    var scrollsInternally: Bool = false

    func makeNSView(context: Context) -> NoScrollWKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "heightChange")
        // 아티팩트 저장 요청 수신 (v2.5 T-123)
        contentController.add(context.coordinator, name: "artifact")
        config.userContentController = contentController

        let webView = NoScrollWKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsInternalVerticalScroll = scrollsInternally
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        let html = context.coordinator.buildHTML(text, appearance: appearance, isStreaming: isStreaming)
        webView.loadHTMLString(html, baseURL: nil)

        return webView
    }

    func updateNSView(_ webView: NoScrollWKWebView, context: Context) {
        let coordinator = context.coordinator

        // 스트리밍 종료 전환 감지 — 버튼 설치를 위해 1회 강제 리로드 (v2.5 T-123)
        let justFinishedStreaming = coordinator.lastIsStreaming && !isStreaming
        coordinator.lastIsStreaming = isStreaming
        if justFinishedStreaming {
            coordinator.isInitialized = false
        }

        // 테마 변경 시 전체 리로드
        if coordinator.lastAppearance != appearance {
            coordinator.lastAppearance = appearance
            coordinator.lastText = text
            coordinator.isInitialized = false
            let html = coordinator.buildHTML(text, appearance: appearance, isStreaming: isStreaming)
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        guard isStreaming else {
            // 스트리밍 완료: 텍스트가 변경되면 전체 리로드
            guard coordinator.lastText != text else { return }
            coordinator.lastText = text
            coordinator.isInitialized = false
            let html = coordinator.buildHTML(text, appearance: appearance, isStreaming: false)
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        // 스트리밍 중: 초기화 안 되었으면 초기화
        if !coordinator.isInitialized {
            coordinator.isInitialized = true
            coordinator.lastText = text
            coordinator.appendChunkToWebView(webView, markdown: text)
            return
        }

        // 스트리밍 중: 텍스트가 변경된 경우에만 점진적 렌더링
        guard coordinator.lastText != text else { return }
        coordinator.lastText = text
        coordinator.appendChunkToWebView(webView, markdown: text)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight, scrollsInternally: scrollsInternally)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var contentHeight: Binding<CGFloat>
        var lastText: String = ""
        var lastAppearance: String = ""
        var isInitialized: Bool = false
        /// 스트리밍 종료 전환 감지용 (v2.5 T-123)
        var lastIsStreaming: Bool = false
        /// 마지막 렌더에서 감지한 아티팩트 — 저장 요청 시 코드 조회
        var lastArtifacts: [ArtifactPreview.Block] = []
        weak var webView: WKWebView?
        static var resourceCache: [String: String] = [:]
        /// 웹 문서 자체 스크롤 모드 (v1.9 T-89) — buildHTML의 CSS 오버라이드 토글
        let scrollsInternally: Bool

        init(contentHeight: Binding<CGFloat>, scrollsInternally: Bool = false) {
            self.contentHeight = contentHeight
            self.scrollsInternally = scrollsInternally
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "heightChange":
                guard let height = message.body as? Double else { return }
                DispatchQueue.main.async {
                    self.contentHeight.wrappedValue = max(CGFloat(height), 20)
                }
            case "artifact":
                handleArtifactMessage(message.body)
            default:
                break
            }
        }

        // MARK: - 아티팩트 저장 (v2.5 T-123)

        private func handleArtifactMessage(_ body: Any) {
            guard let dict = body as? [String: Any],
                  dict["action"] as? String == "download",
                  let index = (dict["index"] as? NSNumber)?.intValue,
                  lastArtifacts.indices.contains(index) else {
                DebugLogger.shared.warn("ARTIFACT", "[E-MAC-UI-1004] 잘못된 아티팩트 저장 요청")
                return
            }
            let block = lastArtifacts[index]
            let panel = NSSavePanel()
            panel.nameFieldStringValue = ArtifactPreview.suggestedFileName(index: index, language: block.language)
            panel.allowedContentTypes = Self.contentTypes(for: block.language)
            DebugLogger.shared.info("ARTIFACT", "저장 요청: \(block.language) #\(index)")

            let window = webView?.window ?? NSApplication.shared.keyWindow
            let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try block.code.write(to: url, atomically: true, encoding: .utf8)
                    DebugLogger.shared.info("ARTIFACT", "저장 완료: \(url.lastPathComponent)")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } catch {
                    DebugLogger.shared.error("ARTIFACT", "[E-MAC-STOR-1001] 저장 실패: \(error.localizedDescription)")
                }
                _ = self // 순환 방지 없음 — 명시적 캡처
            }
            if let window {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                completion(panel.runModal())
            }
        }

        private static func contentTypes(for language: String) -> [UTType] {
            switch language {
            case "svg": return [.svg]
            case "mermaid": return [UTType(filenameExtension: "mmd") ?? .plainText]
            default: return [.html]
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                webView.evaluateJavaScript("document.getElementById('content').scrollHeight") { result, _ in
                    guard let height = result as? CGFloat else { return }
                    self.contentHeight.wrappedValue = max(height, 40)
                }
            }
        }

        // MARK: - 점진적 렌더링

        /// JS 템플릿 리터럴 안전 이스케이프 (백슬래시·백틱·달러)
        private func escapeJSTemplateLiteral(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
        }

        func appendChunkToWebView(_ webView: WKWebView, markdown: String) {
            webView.evaluateJavaScript("appendChunk(`\(escapeJSTemplateLiteral(markdown))`)")
        }

        func finalizeWebView(_ webView: WKWebView) {
            webView.evaluateJavaScript("finalizeMarkdown()")
        }

        // MARK: - HTML 빌드

        func buildHTML(_ markdown: String, appearance: String, isStreaming: Bool) -> String {
            // 아티팩트 감지 — 버튼 인젝터·저장 기능용 (v2.5 T-123)
            let artifacts = ArtifactPreview.detectBlocks(in: markdown)
            lastArtifacts = artifacts
            let artifactsJSON = ArtifactPreview.injectionPayloadText(for: artifacts, appearance: appearance)
            if !artifacts.isEmpty {
                DebugLogger.shared.info("ARTIFACT", "프리뷰 대상 \(artifacts.count)개 감지 (\(artifacts.map(\.language).joined(separator: ",")))")
            }

            let scripts = [loadResource("marked.min"), loadResource("highlight.min"), loadResource("markdown-renderer"), loadResource("artifact-preview")]
                .map { "<script>\($0)</script>" }
                .joined(separator: "\n")

            let escapedMarkdown = escapeJSTemplateLiteral(markdown)

            // 내부 스크롤 모드(고정 높이) — 본문 스크롤 활성화 오버라이드 (v1.9 T-89)
            let scrollStyle = scrollsInternally
                ? "<style>html,body{overflow-y:auto !important;}body{min-height:100%;}</style>"
                : ""

            // 스트리밍: 점진적 렌더링 / 완료: 전체 렌더링 후 높이 보고
            let renderScript: String
            if isStreaming {
                renderScript = """
                initStreaming('content');
                var md = `\(escapedMarkdown)`;
                appendChunk(md);
                """
            } else {
                renderScript = """
                var md = `\(escapedMarkdown)`;
                document.getElementById('content').innerHTML = renderMarkdown(md);
                installArtifactButtons(window.__artifacts);
                requestAnimationFrame(function() {
                  var el = document.getElementById('content');
                  var h = Math.max(el.scrollHeight, el.offsetHeight, 40);
                  window.webkit.messageHandlers.heightChange.postMessage(h);
                });
                """
            }

            return """
            <!DOCTYPE html>
            <html data-theme="\(appearance)">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>\(loadResource("markdown", ext: "css"))</style>
            \(scrollStyle)
            </head>
            <body oncontextmenu="return false">
            <div class="markdown-body" id="content"></div>
            \(scripts)
            <script>
            window.__artifacts = \(artifactsJSON);
            \(renderScript)
            </script>
            </body>
            </html>
            """
        }

        private func loadResource(_ name: String, ext: String = "js") -> String {
            let key = "\(name).\(ext)"
            if let cached = Coordinator.resourceCache[key] {
                return cached
            }
            guard let url = Bundle.main.url(forResource: name, withExtension: ext),
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                return ""
            }
            Coordinator.resourceCache[key] = content
            return content
        }
    }
}
