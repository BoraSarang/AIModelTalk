import Foundation

/// 아티팩트 프리뷰 지원 — 코드펜스 감지·미리보기 문서 생성·파일명 제안 (v2.5 T-123)
/// 순수 로직만 포함 — UI는 MarkdownRenderer의 JS 인젝터가 담당
enum ArtifactPreview {

    /// 프리뷰 가능 언어 별칭 정규화 — react는 스파이크(v2.5 T-124)
    static let supportedLanguages: Set<String> = ["html", "htm", "xhtml", "svg", "mermaid", "react"]

    struct Block: Equatable {
        /// 정규화된 언어 — "html" | "svg" | "mermaid"
        let language: String
        let code: String
    }

    /// 정보 문자열 → 정규화 언어. 미지원이면 nil
    static func normalizedLanguage(_ infoString: String) -> String? {
        let first = infoString
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        let lower = first.lowercased()
        switch lower {
        case "html", "htm", "xhtml":
            return "html"
        case "svg":
            return "svg"
        case "mermaid":
            return "mermaid"
        case "react", "jsx":
            return "react"
        default:
            return nil
        }
    }

    /// 마크다운에서 프리뷰 가능 코드펜스를 문서 순서대로 추출
    /// 규칙: 최대 3칸 들여쓰기 허용, ``` 또는 ~~~ 펜스(3개 이상), 닫힘 없으면 끝까지, 미지원 펜스는 내부 스킵
    static func detectBlocks(in markdown: String) -> [Block] {
        var blocks: [Block] = []
        var language: String?      // 열려 있고 수집 중인 지원 블록의 언어
        var skippingFence = ""     // 미지원 펜스 스킵 중이면 펜스 문자열, 아니면 ""
        var codeLines: [String] = []
        var openFence = ""

        func closeBlock() {
            if let lang = language {
                blocks.append(Block(language: lang, code: codeLines.joined(separator: "\n")))
            }
            language = nil
            codeLines = []
            openFence = ""
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = rawLine.prefix(while: { $0 == " " }).count
            let trimmed = rawLine.dropFirst(min(indent, 3))
            let fenceRun = trimmed.prefix(while: { $0 == "`" || $0 == "~" })

            // 닫는 펜스 — 같은 문자로 3개 이상 + 뒤에 공백만
            let isClosing = (!openFence.isEmpty || !skippingFence.isEmpty)
                && fenceRun.count >= 3
                && fenceRun.first == (openFence.isEmpty ? skippingFence : openFence).first
                && trimmed.dropFirst(fenceRun.count).allSatisfy { $0 == " " || $0 == "\t" }

            if !skippingFence.isEmpty {
                if isClosing { skippingFence = "" }
                continue
            }

            if language != nil {
                if isClosing {
                    closeBlock()
                } else {
                    codeLines.append(String(rawLine))
                }
                continue
            }

            // 밖 — 여는 펜스 판정
            if indent <= 3, fenceRun.count >= 3 {
                let info = trimmed.dropFirst(fenceRun.count).trimmingCharacters(in: .whitespaces)
                if let lang = normalizedLanguage(String(info)) {
                    language = lang
                    openFence = String(fenceRun)
                    codeLines = []
                } else {
                    skippingFence = String(fenceRun)
                }
            }
        }
        // 닫힘 없이 끝난 지원 블록은 끝까지 수집한 것으로 처리
        closeBlock()
        return blocks
    }

    // MARK: - 미리보기 문서 생성

    /// iframe srcdoc에 넣을 완전한 HTML 문서. mermaid는 CDN 래퍼로 감싼다.
    static func previewDocument(language: String, code: String, appearance: String = "light") -> String {
        let escapedAppearance = appearance == "dark" ? "dark" : "light"
        switch language {
        case "html":
            return """
            <!DOCTYPE html><html data-theme="\(escapedAppearance)"><head><meta charset="utf-8">
            <style>body{margin:0;padding:8px;background:#fff;color:#111;font-family:-apple-system,sans-serif;}</style>
            </head><body>\(code)</body></html>
            """
        case "svg":
            return """
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <style>body{margin:0;display:flex;align-items:center;justify-content:center;min-height:100vh;background:#fff;}
            svg{max-width:96%;height:auto;}</style></head><body>\(code)</body></html>
            """
        case "mermaid":
            // sandbox(allow-scripts, same-origin 없음)에서 동작하도록 localStorage 접근 회피
            let safeCode = code
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return """
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <style>body{margin:0;background:#fff;display:flex;justify-content:center;}#graph svg{max-width:98%;height:auto;}</style>
            <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
            </head><body><pre id="src" style="display:none">\(safeCode)</pre><div id="graph"></div>
            <script>
            try {
              var src = document.getElementById('src').textContent;
              var theme = document.documentElement.dataset.theme === 'dark' ? 'dark' : 'default';
              mermaid.initialize({ startOnLoad: false, theme: theme });
              mermaid.render('m' + Date.now(), src).then(function(r) {
                document.getElementById('graph').innerHTML = r.svg;
              }).catch(function(e) {
                document.getElementById('graph').textContent = '렌더링 실패: ' + e.message;
              });
            } catch (e) {
              document.getElementById('graph').textContent = '렌더링 실패: ' + e.message;
            }
            </script></body></html>
            """
        case "react":
            // 스파이크(v2.5 T-124): Babel standalone로 JSX 트랜스파일 후 렌더
            return """
            <!DOCTYPE html><html data-theme="\(escapedAppearance)"><head><meta charset="utf-8">
            <style>body{margin:0;padding:8px;background:#fff;color:#111;font-family:-apple-system,sans-serif;}
            html[data-theme="dark"] body{background:#1e1e1e;color:#eee;}
            .art-error{color:#c0392b;font:12px monospace;white-space:pre-wrap;}</style>
            <script>
            window.addEventListener('error', function(e){
              var r=document.getElementById('root');
              if(r && !r.hasChildNodes()){
                r.innerHTML='<div class="art-error">렌더링 실패: '+((e&&e.message)||'알 수 없는 오류')+'</div>';
              }
            });
            </script>
            <script crossorigin src="https://cdn.jsdelivr.net/npm/react@18/umd/react.production.min.js"></script>
            <script crossorigin src="https://cdn.jsdelivr.net/npm/react-dom@18/umd/react-dom.production.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/@babel/standalone/babel.min.js"></script>
            </head><body><div id="root"></div>
            <script type="text/babel">
            \(code)
            ;(function(){
              var r=document.getElementById('root');
              if(r && !r.hasChildNodes()){
                try{
                  if(typeof App!=='undefined'){ReactDOM.createRoot(r).render(React.createElement(App));}
                  else{r.textContent='렌더 호출 없음 — createRoot(...).render(...)가 필요합니다.';}
                }catch(err){r.textContent='렌더링 실패: '+err.message;}
              }
            })();
            </script></body></html>
            """
        default:
            return ""
        }
    }

    // MARK: - 다운로드

    /// 저장 파일명 제안 — artifact-1.html 형태
    static func suggestedFileName(index: Int, language: String) -> String {
        let ext: String
        switch language {
        case "svg": ext = "svg"
        case "mermaid": ext = "mmd"
        case "react": ext = "jsx"
        default: ext = "html"
        }
        return "artifact-\(index + 1).\(ext)"
    }

    /// JS 주입용 artifacts JSON 배열 데이터 — [ [lang, doc], ... ]
    /// 반환 텍스트는 `window.__artifacts = <반환값>;` 형태로 스크립트에 직접 삽입한다.
    /// `</`는 JSON 문자열 이스케이프 `<\/`로 치환 — 외부 <script> 블록 조기 종료 방지
    static func injectionPayloadText(for blocks: [Block], appearance: String) -> String {
        let payload: [[String]] = blocks.map { block in
            [block.language, previewDocument(language: block.language, code: block.code, appearance: appearance)]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        text = text.replacingOccurrences(of: "</", with: "<\\/")
        return text
    }
}
