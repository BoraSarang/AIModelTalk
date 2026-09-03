import Foundation

enum TokenEstimator {
    /// 대략적인 토큰 수 추정
    /// - 한글/중국어/일본어: 글자 1개 ≈ 1 토큰
    /// - 영문: 단어 1개 ≈ 1.3 토큰 (공백 분리 기준)
    /// - 혼합 텍스트: 문자별 언어 판별
    static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var koreanCount = 0
        var cjkCount = 0
        var englishWords = 0
        var otherChars = 0

        let englishPattern = try? NSRegularExpression(pattern: "[A-Za-z0-9]+")
        let nsRange = NSRange(text.startIndex..., in: text)

        // 영문 단어 추출
        if let matches = englishPattern?.matches(in: text, range: nsRange) {
            englishWords = matches.count
            let matchedLength = matches.reduce(0) { $0 + $1.range.length }
            otherChars = text.count - (matchedLength) // 대략적
        }

        for char in text {
            if (0xAC00...0xD7A3).contains(char.unicodeScalars.first?.value ?? 0) {
                koreanCount += 1
            } else if (0x3040...0x30FF).contains(char.unicodeScalars.first?.value ?? 0) ||
                      (0x4E00...0x9FFF).contains(char.unicodeScalars.first?.value ?? 0) {
                cjkCount += 1
            }
        }

        // 영문 외 문자수 (한글+CJK+기타)
        let nonEnglish = text.count - (englishWords > 0 ? text.components(separatedBy: .whitespacesAndNewlines).joined().filter { $0.isASCII && $0.isLetter }.count : 0)

        let estimated = Double(koreanCount + cjkCount) * 1.0
                      + Double(englishWords) * 1.3
                      + Double(max(0, otherChars - koreanCount - cjkCount)) * 0.5

        return Int(ceil(estimated))
    }

    /// 전체 대화 컨텍스트 토큰 추정 (시스템 프롬프트 + 모든 메시지)
    static func estimateConversation(systemPrompt: String, messages: [ChatMessage]) -> Int {
        var total = estimate(systemPrompt)
        for msg in messages {
            total += estimate(msg.content) + 4 // 메시지 오버헤드
        }
        return total
    }
}
