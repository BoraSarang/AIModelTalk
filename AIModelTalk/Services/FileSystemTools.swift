import Foundation

/// 워크스페이스 폴더 기반 파일 I/O 도구 (v0.3.0 축3) — 경로 샌드박스 적용
/// 지정된 워크스페이스 폴더 안에서만 list_dir/read_file/write_file/edit_file 수행.
/// 워크스페이스 미지정 시 모든 도구가 비활성(실패) 처리 — 절대 경로 탈출 방지.
@MainActor
enum FileSystemTools {

    struct FileToolError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 워크스페이스 폴더 미지정 여부 (도구 등록 시 비활성 판단)
    static var isAvailable: Bool {
        !(AppSettings.shared.workspaceFolder ?? "").isEmpty
    }

    /// 시스템 프롬프트용 워크스페이스 개요 (v0.3.0 축3) — 루트 경로 + 상위 2레벨 트리 요약
    static func promptOverview() -> String {
        guard let path = AppSettings.shared.workspaceFolder, !path.isEmpty else { return "" }
        var lines = ["\n\n## 워크스페이스 (로컬 프로젝트 폴더)",
                     "루트: \(path)",
                     "작업은 이 폴더 안에서만 가능합니다. 아래는 상위 2레벨 파일 트리 요약입니다."]
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for item in items.prefix(60) {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    lines.append("\(item.lastPathComponent)/")
                    if let sub = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                        for s in sub.prefix(20) {
                            lines.append("  \(s.lastPathComponent)\(((try? s.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) ? "/" : "")")
                        }
                    }
                } else {
                    lines.append(item.lastPathComponent)
                }
            }
            if items.count > 60 { lines.append("…외 \(items.count - 60)개 항목") }
        }
        return lines.joined(separator: "\n")
    }

    private static var rootURL: URL? {
        guard let path = AppSettings.shared.workspaceFolder, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// 경로 검증 — 워크스페이스 루트 안에 있는 표준화 경로인지 (샌드박스)
    private static func resolve(_ raw: String, allowDir: Bool = false) throws -> URL {
        guard let root = rootURL else {
            throw FileToolError(message: "워크스페이스 폴더가 설정되지 않았습니다. 설정 → 일반 → 워크스페이스 폴더에서 지정해 주세요.")
        }
        // 상대 경로는 루트 기준, 절대 경로는 그대로 → 표준화 후 루트 내부인지 검사
        var base = root
        if raw.hasPrefix("/") {
            base = URL(fileURLWithPath: "/")
        }
        let resolved = URL(fileURLWithPath: raw, relativeTo: base).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        let targetPath = resolved.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            throw FileToolError(message: "경로가 워크스페이스 폴더 밖입니다: \(targetPath)")
        }
        if !allowDir {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDir), isDir.boolValue {
                throw FileToolError(message: "디렉터리입니다 (파일이어야 함): \(targetPath)")
            }
        }
        return URL(fileURLWithPath: targetPath)
    }

    // MARK: - 도구 실행

    /// list_dir — 폴더 내 항목(이름·타입·크기) 요약
    static func listDir(arguments: [String: Any]) throws -> String {
        guard let path = arguments["path"] as? String else {
            throw FileToolError(message: "경로(path)가 필요합니다.")
        }
        let dirURL = try resolve(path, allowDir: true)
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let contents = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var lines = ["[\(dirURL.path) — \(contents.count)개 항목]"]
        for item in contents {
            let values = try? item.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            let size = isDir ? "" : (values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "")
            lines.append("\(isDir ? "📁" : "📄") \(item.lastPathComponent) \(size)")
        }
        return lines.joined(separator: "\n")
    }

    /// read_file — 텍스트 파일 내용 (미리보기 상한)
    static func readFile(arguments: [String: Any]) throws -> String {
        guard let path = arguments["path"] as? String else {
            throw FileToolError(message: "경로(path)가 필요합니다.")
        }
        let url = try resolve(path)
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw FileToolError(message: "UTF-8 텍스트가 아니어서 읽을 수 없습니다: \(url.lastPathComponent)")
        }
        let limit = 12_000
        if text.count > limit {
            return "⚠️ 파일이 큼 — 처음 \(limit)자만 표시 (전체 \(text.count)자)\n" + String(text.prefix(limit))
        }
        return text
    }

    /// write_file — 새 파일 생성 또는 덮어쓰기
    static func writeFile(arguments: [String: Any]) throws -> String {
        guard let path = arguments["path"] as? String, let content = arguments["content"] as? String else {
            throw FileToolError(message: "경로(path)와 내용(content)이 필요합니다.")
        }
        let url = try resolve(path)
        try url.deletingLastPathComponent().ensureDirectory()
        try content.data(using: .utf8)?.write(to: url, options: .atomic)
        return "✔️ 파일 저장: \(url.path) (\(content.count)자)"
    }

    /// edit_file — 라인 단위 치환(대치). oldContent/newContent를 주면 첫 일치 블록 치환.
    static func editFile(arguments: [String: Any]) throws -> String {
        guard let path = arguments["path"] as? String,
              let oldText = arguments["oldContent"] as? String,
              let newText = arguments["newContent"] as? String else {
            throw FileToolError(message: "경로(path), oldContent, newContent가 필요합니다.")
        }
        let url = try resolve(path)
        let data = try Data(contentsOf: url)
        guard var text = String(data: data, encoding: .utf8) else {
            throw FileToolError(message: "UTF-8 텍스트가 아니어서 편집할 수 없습니다: \(url.lastPathComponent)")
        }
        guard let range = text.range(of: oldText) else {
            throw FileToolError(message: "치환 대상을 찾지 못했습니다: '\(String(oldText.prefix(80)))'")
        }
        text.replaceSubrange(range, with: newText)
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
        return "✔️ 파일 편집 완료: \(url.lastPathComponent)"
    }
}

private extension URL {
    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
    }
}
