import Foundation

enum SessionExportService {

    // MARK: - JSON (백업용, 전체 충실도)

    static func exportJSON(_ session: ChatSession) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(session)
    }

    static func importJSON(_ data: Data) throws -> ChatSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(ChatSession.self, from: data)
        return session
    }

    // MARK: - Markdown (공유용, 가독)

    static func exportMarkdown(_ session: ChatSession) -> String {
        var lines: [String] = []
        lines.append("# \(session.title)")
        lines.append("")
        lines.append("- 생성: \(formatDate(session.createdAt))")
        lines.append("- 모델: \(session.currentModel?.displayName ?? "알 수 없음")")
        lines.append("")

        for message in session.messages {
            let roleName = message.role == .user ? "👤 사용자" : "🤖 AI"
            lines.append("## \(roleName)")
            lines.append("")
            lines.append(message.content)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
}
