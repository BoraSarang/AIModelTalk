import SwiftUI
import Splash

// MARK: - CodeBlockView (간단 하이라이트 + 복사 버튼)

/// 코드 블록 렌더링 — 언어 라벨, 호버 시 복사 버튼
/// Splash 의존성 없이 간단 구현 (추후 Splash로 교체 가능)
struct CodeBlockView: View {
    @Environment(\.theme) private var theme
    let code: String
    let language: String
    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더: 언어 라벨 + 복사 버튼
            HStack {
                Text(languageDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryText)

                Spacer()

                if isHovered {
                    Button(action: copyCode) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .help(copied ? "복사됨" : "코드 복사")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.tertiaryBackground.opacity(0.5))

            // 코드 영역 (간단 하이라이트 적용)
            ScrollView(.horizontal) {
                HighlightedCodeText(code: code, language: language, theme: theme.value)
                    .font(.system(size: theme.codeSize, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.cardBorder.opacity(theme.borderOpacity), lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
    }

    private var languageDisplayName: String {
        if language.isEmpty { return "코드" }
        return language.capitalized
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { copied = false }
        }
    }
}

// MARK: - HighlightedCodeText (Swift=Splash, 타언어=정규식) (T-320)

/// 하이라이트 엔진 선택 — 순수 함수 (테스트 가능)
enum CodeHighlightEngine {
    case splash
    case regex
}

struct CodeHighlightProvider {
    /// Splash 문법은 Swift 전용이라 Swift만 Splash, 나머지는 정규식 유지
    static func engine(for language: String) -> CodeHighlightEngine {
        language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "swift" ? .splash : .regex
    }
}

/// 앱 테마 → Splash 테마 매핑 (Splash 0.16 AppKit 기반)
struct AppSplashTheme {
    static func make(codeSize: CGFloat) -> Splash.Theme {
        func c(_ hex: String) -> NSColor { NSColor(hexString: hex) ?? .textColor }
        return Splash.Theme(
            font: Splash.Font(size: Double(codeSize)),
            plainTextColor: .textColor,
            tokenColors: [
                .keyword: c("e06c75"),
                .string: c("98c379"),
                .type: c("e5c07b"),
                .number: c("d19a66"),
                .comment: .tertiaryLabelColor,
                .call: c("61afef"),
                .property: c("61afef"),
                .dotAccess: c("61afef"),
                .preprocessing: c("e5c07b"),
            ],
            backgroundColor: .clear
        )
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        self.init(calibratedRed: r, green: g, blue: b, alpha: 1.0)
    }
}

struct HighlightedCodeText: View {
    let code: String
    let language: String
    let theme: any ThemeProtocol

    var body: some View {
        Text(highlighted)
    }

    private var highlighted: AttributedString {
        if CodeHighlightProvider.engine(for: language) == .splash {
            let format = AttributedStringOutputFormat(theme: AppSplashTheme.make(codeSize: theme.codeSize))
            let highlighter = SyntaxHighlighter(format: format)
            let nsResult: NSAttributedString = highlighter.highlight(code)
            return AttributedString(nsResult)
        }
        return highlightCode(code, language: language)
    }

    private func highlightCode(_ code: String, language: String) -> AttributedString {
        var result = AttributedString()
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)

        let keywords: Set<String> = keywordsForLanguage(language)
        let types: Set<String> = typesForLanguage(language)
        let comments: Set<String> = commentPatternsForLanguage(language)

        for (lineIndex, line) in lines.enumerated() {
            var lineStr = String(line)
            var attrLine = AttributedString()

            // 주석 처리
            if let commentStart = lineStr.firstIndex(of: "/") {
                let nextIdx = lineStr.index(after: commentStart)
                if nextIdx < lineStr.endIndex && lineStr[nextIdx] == "/" {
                    // 라인 전체 주석
                    var comment = AttributedString(lineStr)
                    comment.foregroundColor = theme.tertiaryText
                    comment.font = theme.monoFont(size: theme.codeSize)
                    return comment
                }
            }

            // 토큰별 하이라이트
            let tokens = tokenize(lineStr, keywords: keywords, types: types)
            for token in tokens {
                var attrToken = AttributedString(token.text)
                attrToken.font = theme.monoFont(size: theme.codeSize)
                switch token.type {
                case .keyword: attrToken.foregroundColor = Color(hex: "e06c75") ?? theme.accentColor
                case .type: attrToken.foregroundColor = Color(hex: "e5c07b") ?? theme.warningColor
                case .string: attrToken.foregroundColor = Color(hex: "98c379") ?? theme.successColor
                case .number: attrToken.foregroundColor = Color(hex: "d19a66") ?? theme.accentColor
                case .comment: attrToken.foregroundColor = theme.tertiaryText
                case .function: attrToken.foregroundColor = Color(hex: "61afef") ?? theme.infoColor
                default: attrToken.foregroundColor = theme.primaryText
                }
                result.append(attrToken)
            }

            // 줄바꿈 추가 (마지막 줄 제외)
            if lineIndex < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }

        return result
    }

    private struct Token {
        let text: String
        let type: TokenType
    }

    private enum TokenType {
        case keyword, type, string, number, comment, function, plain
    }

    private func tokenize(_ line: String, keywords: Set<String>, types: Set<String>) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var i = line.startIndex

        while i < line.endIndex {
            let char = line[i]

            // 문자열 리터럴
            if char == "\"" || char == "'" {
                if !current.isEmpty {
                    tokens.append(Token(text: current, type: .plain))
                    current = ""
                }
                let quote = char
                current.append(char)
                i = line.index(after: i)
                while i < line.endIndex && line[i] != quote {
                    current.append(line[i])
                    i = line.index(after: i)
                }
                if i < line.endIndex {
                    current.append(line[i]) // closing quote
                    i = line.index(after: i)
                }
                tokens.append(Token(text: current, type: .string))
                current = ""
                continue
            }

            // 숫자
            if char.isNumber {
                current.append(char)
                i = line.index(after: i)
                while i < line.endIndex && (line[i].isNumber || line[i] == ".") {
                    current.append(line[i])
                    i = line.index(after: i)
                }
                tokens.append(Token(text: current, type: .number))
                current = ""
                continue
            }

            // 연산자/구두점
            if "+-*/=<>!&|.,;:()[]{}".contains(char) {
                if !current.isEmpty {
                    tokens.append(classifyToken(current, keywords: keywords))
                    current = ""
                }
                tokens.append(Token(text: String(char), type: .plain))
                i = line.index(after: i)
                continue
            }

            // 공백
            if char.isWhitespace {
                if !current.isEmpty {
                    tokens.append(classifyToken(current, keywords: keywords))
                    current = ""
                }
                current.append(char)
                i = line.index(after: i)
                while i < line.endIndex && line[i].isWhitespace {
                    current.append(line[i])
                    i = line.index(after: i)
                }
                tokens.append(Token(text: current, type: .plain))
                current = ""
                continue
            }

            // 일반 문자
            current.append(char)
            i = line.index(after: i)
        }

        if !current.isEmpty {
            tokens.append(classifyToken(current, keywords: keywords))
        }

        return tokens
    }

    private func classifyToken(_ text: String, keywords: Set<String>) -> Token {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if keywords.contains(trimmed) { return Token(text: text, type: .keyword) }
        // 타입/함수 등은 간단히 처리
        return Token(text: text, type: .plain)
    }

    private func keywordsForLanguage(_ lang: String) -> Set<String> {
        switch lang.lowercased() {
        case "swift":
            return ["func", "var", "let", "if", "else", "for", "while", "return", "class", "struct", "enum", "protocol", "extension", "import", "public", "private", "internal", "static", "mutating", "async", "await", "try", "catch", "throw", "guard", "defer", "switch", "case", "default", "break", "continue", "in", "where", "as", "is", "init", "deinit", "subscript", "operator", "precedencegroup", "associatedtype", "typealias", "generic", "where", "Some", "Any", "Self", "self", "super", "nil", "true", "false"]
        case "python":
            return ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "raise", "with", "lambda", "yield", "async", "await", "True", "False", "None"]
        case "javascript", "typescript":
            return ["function", "const", "let", "var", "if", "else", "for", "while", "return", "class", "import", "export", "async", "await", "try", "catch", "finally", "throw", "new", "this", "super", "extends", "static", "get", "set", "true", "false", "null", "undefined"]
        default:
            return []
        }
    }

    private func typesForLanguage(_ lang: String) -> Set<String> {
        switch lang.lowercased() {
        case "swift":
            return ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Error", "Data", "Date", "URL", "JSONEncoder", "JSONDecoder"]
        default:
            return []
        }
    }

    private func commentPatternsForLanguage(_ lang: String) -> Set<String> {
        return ["//", "/*", "*/"]
    }
}

// MARK: - Markdown Code Block Wrapper

struct MarkdownCodeBlock: View {
    @Environment(\.theme) private var theme
    let code: String
    let language: String

    var body: some View {
        CodeBlockView(code: code, language: language)
    }
}

// MARK: - InlineCodeView

struct InlineCodeView: View {
    @Environment(\.theme) private var theme
    let code: String

    var body: some View {
        Text(code)
            .font(.system(size: theme.codeSize, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.cardBackground.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Preview

#Preview("CodeBlockView") {
    let sampleCode = """
    func greet(name: String) -> String {
        return "Hello, \\(name)!"
    }

    let message = greet(name: "World")
    print(message)
    """

    CodeBlockView(code: sampleCode, language: "swift")
        .padding()
        .environment(\.theme, ThemeBox(LightTheme()))
}

#Preview("InlineCodeView") {
    Text("Run `npm install` to set up dependencies.")
        .font(.system(size: 13))
        .environment(\.theme, ThemeBox(LightTheme()))
}