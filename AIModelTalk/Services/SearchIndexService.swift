import Foundation
import SQLite3

/// 전역 메시지 검색 인덱스 — 별도 SQLite FTS5 DB (v1.9 T-77, PLAN_v1.9 D6)
/// SwiftData 저장소와 분리된 캐시 성격 파일이며, 손상 시 삭제 후 재색인 가능.
/// 토크나이저는 trigram(부분 일치) — 3자 미만 질의 또는 무결과 시 LIKE 폴백으로 한글 2자 검색 지원.
final class SearchIndexService {
    struct SearchHit: Identifiable {
        let id: UUID            // messageID
        let sessionID: UUID
        let messageID: UUID
        let role: String
        let snippet: String
        let updatedAt: Date?
    }

    static let shared = SearchIndexService()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.borasarang.aiModelTalk.searchIndex")

    init(inMemory: Bool = false) {
        let path = inMemory ? ":memory:" : Self.defaultDBPath().path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              db != nil else {
            DebugLogger.shared.error("SEARCH", "[E-MAC-DB-1001] 검색 DB 열기 실패: \(path)")
            db = nil
            return
        }
        exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS messages USING fts5(
            content,
            session_id UNINDEXED,
            message_id UNINDEXED,
            role UNINDEXED,
            updated_at UNINDEXED,
            tokenize='trigram'
        )
        """)
        DebugLogger.shared.info("APP", "[FEATURE] 검색 인덱스 초기화됨: \(inMemory ? "in-memory" : path)")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    static func defaultDBPath() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIModelTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app-search.db")
    }

    // MARK: - 쓰기

    /// 세션 전체 재색인 — 기존 행 삭제 후 현재 메시지 삽입 (saveSession 진입점에서 호출)
    func index(_ session: ChatSession) {
        queue.sync {
            removeInternal(sessionID: session.id)
            exec("BEGIN")
            // 세션 제목 행 — role="title", message_id=세션 ID (v2.1 T-97 제목 검색)
            insertRow(content: session.title, sessionID: session.id,
                      messageID: session.id, role: "title", updatedAt: session.updatedAt)
            for message in session.messages where !message.content.isEmpty {
                insertRow(content: message.content, sessionID: session.id,
                          messageID: message.id, role: message.role.rawValue,
                          updatedAt: session.updatedAt)
            }
            exec("COMMIT")
        }
    }

    /// 전체 재구축 — 인덱스가 비어 있고 세션이 있을 때 1회 실행
    func reindexIfEmpty(sessions: [ChatSession]) {
        queue.sync {
            guard totalCountInternal() == 0, !sessions.isEmpty else { return }
            exec("BEGIN")
            for session in sessions {
                insertRow(content: session.title, sessionID: session.id,
                          messageID: session.id, role: "title", updatedAt: session.updatedAt)
                for message in session.messages where !message.content.isEmpty {
                    insertRow(content: message.content, sessionID: session.id,
                              messageID: message.id, role: message.role.rawValue,
                              updatedAt: session.updatedAt)
                }
            }
            exec("COMMIT")
            DebugLogger.shared.info("APP", "[FEATURE] 검색 인덱스 전체 재구축 실행됨: \(sessions.count)개 세션")
        }
    }

    func remove(sessionID: UUID) {
        queue.sync { removeInternal(sessionID: sessionID) }
    }

    func totalCount() -> Int {
        queue.sync { totalCountInternal() }
    }

    // MARK: - 읽기

    /// FTS5(trigram) 우선 → 무결과 또는 2자 질의는 LIKE 폴백 (한글 2자어 대응)
    func search(_ rawQuery: String, limit: Int = 50) -> [SearchHit] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard db != nil, query.count >= 2 else { return [] }
        var hits: [SearchHit] = []
        queue.sync {
            if query.count >= 3 {
                hits = ftsSearch(query, limit: limit)
            }
            if hits.isEmpty {
                hits = likeSearch(query, limit: limit)
            }
        }
        return hits
    }

    // MARK: - 내부 (queue.sync 내부에서만 호출)

    private func removeInternal(sessionID: UUID) {
        exec("DELETE FROM messages WHERE session_id = '\(sessionID.uuidString)'")
    }

    private func totalCountInternal() -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM messages", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func insertRow(content: String, sessionID: UUID, messageID: UUID,
                           role: String, updatedAt: Date) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "INSERT INTO messages(content, session_id, message_id, role, updated_at) VALUES (?, ?, ?, ?, ?)", -1, &stmt, nil) == SQLITE_OK else { return }
        bindText(stmt, 1, content)
        bindText(stmt, 2, sessionID.uuidString)
        bindText(stmt, 3, messageID.uuidString)
        bindText(stmt, 4, role)
        bindText(stmt, 5, Self.stringFromDate(updatedAt))
        sqlite3_step(stmt)
    }

    private func ftsSearch(_ query: String, limit: Int) -> [SearchHit] {
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        let match = "\"\(escaped)\""
        let sql = """
        SELECT snippet(messages, 0, '', '', '…', 14),
               session_id, message_id, role, updated_at
        FROM messages WHERE messages MATCH ?
        ORDER BY rank LIMIT \(limit)
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        bindText(stmt, 1, match)
        return collectRows(stmt)
    }

    private func likeSearch(_ query: String, limit: Int) -> [SearchHit] {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let sql = """
        SELECT content, session_id, message_id, role, updated_at
        FROM messages WHERE content LIKE '%\(escaped)%' ESCAPE '\\'
        LIMIT \(limit * 4)
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        return collectRows(stmt, limit: limit) { Self.makeSnippet($0, needle: query) }
    }

    private func collectRows(_ stmt: OpaquePointer?, limit: Int = 50, snippetOverride: ((String) -> String)? = nil) -> [SearchHit] {
        var hits: [SearchHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW, hits.count < limit {
            guard let cText = sqlite3_column_text(stmt, 0),
                  let sText = sqlite3_column_text(stmt, 1),
                  let mText = sqlite3_column_text(stmt, 2) else { continue }
            let content = String(cString: cText)
            let snippet = snippetOverride?(content) ?? content
            guard let sessionID = UUID(uuidString: String(cString: sText)),
                  let messageID = UUID(uuidString: String(cString: mText)) else { continue }
            let role = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let date = sqlite3_column_text(stmt, 4).map { Self.parseDate(String(cString: $0)) } ?? nil
            hits.append(SearchHit(
                id: messageID,
                sessionID: sessionID,
                messageID: messageID,
                role: role,
                snippet: snippet.replacingOccurrences(of: "\n", with: " "),
                updatedAt: date
            ))
        }
        return hits
    }

    // MARK: - 저수준 헬퍼

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(err) }
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            if let err {
                DebugLogger.shared.warn("SEARCH", "[E-MAC-DB-1001] SQL 실패: \(String(cString: err))")
            }
            return false
        }
        return true
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private static func makeSnippet(_ content: String, needle: String) -> String {
        guard let range = content.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(content.prefix(70))
        }
        let start = content.index(range.lowerBound, offsetBy: -30, limitedBy: content.startIndex) ?? content.startIndex
        let end = content.index(range.upperBound, offsetBy: 45, limitedBy: content.endIndex) ?? content.endIndex
        var snippet = String(content[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if start > content.startIndex { snippet = "…" + snippet }
        if end < content.endIndex { snippet += "…" }
        return snippet
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private static func stringFromDate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func parseDate(_ text: String) -> Date? {
        isoFormatter.date(from: text)
    }
}
