import Foundation
import AppKit

struct ReleaseInfo: Identifiable, Codable {
    let id = UUID()
    let tagName: String
    let name: String
    let htmlURL: String
    let publishedAt: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case body
    }

    var version: String {
        tagName.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespaces)
    }
}

@MainActor
final class UpdateCheckService: ObservableObject {
    static let shared = UpdateCheckService()

    static let repoOwner = "borasarang"
    static let repoName = "AIModelTalk"

    @Published var latestRelease: ReleaseInfo?
    @Published var isChecking = false
    @Published var lastCheckedAt: Date?
    @Published var errorMessage: String?

    var currentVersion: String {
        let dict = Bundle.main.infoDictionary
        return (dict?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    var hasUpdate: Bool {
        guard let latest = latestRelease else { return false }
        return isNewer(latest.version, currentVersion)
    }

    func checkForUpdates() async {
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest") else {
            errorMessage = "잘못된 업데이트 URL입니다."
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                // 릴리즈가 아직 없음 — 정상으로 처리
                latestRelease = nil
                lastCheckedAt = Date()
                return
            }
            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            latestRelease = release
            lastCheckedAt = Date()
        } catch {
            errorMessage = "업데이트 확인 실패: \(error.localizedDescription)"
            DebugLogger.shared.error("E-MAC-NET-2001", errorMessage ?? "")
        }
    }

    func openReleasePage() {
        guard let release = latestRelease, let url = URL(string: release.htmlURL) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 버전 비교 (semver 단순 비교)
    private func isNewer(_ lhs: String, _ rhs: String) -> Bool {
        let l = lhs.split(separator: ".").compactMap { Int($0) }
        let r = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(l.count, r.count)
        for i in 0..<count {
            let lv = l.count > i ? l[i] : 0
            let rv = r.count > i ? r[i] : 0
            if lv != rv {
                return lv > rv
            }
        }
        return false
    }
}
