import Foundation

/// stdio MCP 실행 파일 절대경로 탐색기 (T-342)
/// `MCPConnection.launchProcess`는 `executableURL`에 절대경로를 요구하므로
/// "npx" 같은 베어 명령은 여기서 실제 경로로 바꾼다.
enum MCPExecutableResolver {

    enum ResolveError: LocalizedError {
        case notFound(String)
        var errorDescription: String? {
            switch self {
            case .notFound(let cmd):
                return "[E-MAC-MCP-1001] MCP 실행 파일을 찾을 수 없습니다: \(cmd)"
            }
        }
    }

    /// 고정 탐색 디렉토리 — Homebrew·시스템 순서
    static var searchDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    /// 명령어를 실행 가능한 절대경로로 변환. 실패 시 throw.
    static func resolve(_ command: String) throws -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ResolveError.notFound(command) }
        if trimmed.hasPrefix("/") {
            if FileManager.default.isExecutableFile(atPath: trimmed) { return trimmed }
            DebugLogger.shared.error("MCP", "[E-MAC-MCP-1001] 실행 파일이 없거나 실행 불가: \(trimmed)")
            throw ResolveError.notFound(trimmed)
        }
        for dir in searchDirectories {
            let path = (dir as NSString).appendingPathComponent(trimmed)
            if FileManager.default.isExecutableFile(atPath: path) {
                DebugLogger.shared.info("MCP", "[FEATURE] 실행 파일 탐색: \(trimmed) → \(path)")
                return path
            }
        }
        // nvm 등 가변 경로: ~/.nvm/versions/node/*/bin (최신 버전 우선)
        let nvmBin = (NSHomeDirectory() as NSString).appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmBin) {
            for version in versions.sorted().reversed() {
                let path = ((nvmBin as NSString).appendingPathComponent(version) as NSString)
                    .appendingPathComponent("bin/\(trimmed)")
                if FileManager.default.isExecutableFile(atPath: path) {
                    DebugLogger.shared.info("MCP", "[FEATURE] 실행 파일 탐색(nvm): \(trimmed) → \(path)")
                    return path
                }
            }
        }
        if let viaPATH = lookupViaShell(trimmed) {
            DebugLogger.shared.info("MCP", "[FEATURE] 실행 파일 탐색(PATH): \(trimmed) → \(viaPATH)")
            return viaPATH
        }
        DebugLogger.shared.error("MCP", "[E-MAC-MCP-1001] 실행 파일 미발견: \(trimmed)")
        throw ResolveError.notFound(trimmed)
    }

    /// 로그인 셸 경유 최후 탐색 — 따옴표 이스케이프로 인젝션 방지
    private static func lookupViaShell(_ command: String) -> String? {
        let escaped = command.replacingOccurrences(of: "'", with: "'\\''")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-l", "-c", "command -v '\(escaped)'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let found = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard found.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: found) else { return nil }
        return found
    }
}
