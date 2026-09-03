import Foundation

/// 디버그 로그 레벨
enum LogLevel: String, CaseIterable {
    case debug   = "DEBUG"
    case info    = "INFO"
    case warn    = "WARN"
    case error   = "ERROR"
    case perf    = "PERF"
    case cache   = "CACHE"
}

/// 단일 로그 엔트리
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let tag: String
    let message: String
    let file: String
    let line: Int

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }

    var display: String {
        "[\(formattedTime)] [\(level.rawValue)] [\(tag)] \(message)"
    }
}

/// 구조화된 디버그 로거 — 싱글턴
final class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    @Published var entries: [LogEntry] = []
    private let maxEntries = 500
    private let queue = DispatchQueue(label: "com.borasarang.AIModelTalk.logger", qos: .utility)

    private init() {
        // 세션 범위 로그 — 실행마다 파일 초기화
        try? FileManager.default.removeItem(at: Self.logFileURL)
    }

    // MARK: - 공용 API

    func log(_ level: LogLevel, _ tag: String, _ message: String,
             file: String = #file, line: Int = #line) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            tag: tag,
            message: message,
            file: (file as NSString).lastPathComponent,
            line: line
        )
        queue.async { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.entries.append(entry)
                if self.entries.count > self.maxEntries {
                    self.entries.removeFirst(self.entries.count - self.maxEntries)
                }
            }
            Self.appendToFile(entry.display)
        }
        // 콘솔 출력
        print(entry.display)
    }

    // MARK: - 파일 싱크 (v2.1 T-109 후속) — 세션 단절 대비 디스크 진단

    /// ~/Library/Logs/AIModelTalk/debug.log — 실행마다 새로 씀(세션 범위 명확화), 1MB 상한
    private static let logFileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/AIModelTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    private static func appendToFile(_ line: String) {
        let path = logFileURL.path
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            if handle.seekToEndOfFile() > 1_000_000 { // 1MB 상한 — 선두 절반 절단
                let data = handle.readDataToEndOfFile()
                handle.truncateFile(atOffset: 0)
                handle.write(data.suffix(512_000))
            }
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
        } else {
            try? (line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - 편의 메서드

    func debug(_ tag: String, _ message: String,
               file: String = #file, line: Int = #line) {
        log(.debug, tag, message, file: file, line: line)
    }

    func info(_ tag: String, _ message: String,
              file: String = #file, line: Int = #line) {
        log(.info, tag, message, file: file, line: line)
    }

    func warn(_ tag: String, _ message: String,
              file: String = #file, line: Int = #line) {
        log(.warn, tag, message, file: file, line: line)
    }

    func error(_ tag: String, _ message: String,
               file: String = #file, line: Int = #line) {
        log(.error, tag, message, file: file, line: line)
    }

    /// [PERF] 로그 — 성능 측정용
    /// 형식: [HH:mm:ss.SSS] [PERF] [PLATFORM] action=X duration=123ms | meta={...}
    func perf(_ tag: String, _ message: String,
              file: String = #file, line: Int = #line) {
        log(.perf, tag, message, file: file, line: line)
    }

    /// [CACHE] 로그 — 캐시 히트/미스 기록
    /// 형식: [HH:mm:ss.SSS] [CACHE] [PLATFORM] hit=true cost_saved=0.02 | meta={model, prompt_version}
    func cache(_ tag: String, _ message: String,
               file: String = #file, line: Int = #line) {
        log(.cache, tag, message, file: file, line: line)
    }

    /// AppError를 로그 + 에러코드 포함
    func logError(_ tag: String, _ error: Error,
                  file: String = #file, line: Int = #line) {
        let appError = error as? AppError
        let code = appError?.errorCode ?? "E-UNKNOWN"
        let desc = error.localizedDescription
        log(.error, tag, "[\(code)] \(desc)", file: file, line: line)
    }

    /// 로그 전체 텍스트 덤프 (DebugPanel 복사용)
    func dump() -> String {
        entries.map(\.display).joined(separator: "\n")
    }

    /// 로그 클리어
    func clear() {
        entries.removeAll()
    }
}

// MARK: - 하위 호환 별칭

typealias BGLogger = DebugLogger
