import SwiftUI

// MARK: - MCP 서버 관리 설정 화면 (v2.4 T-121)

struct MCPSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var store = MCPServerStore.shared
    /// 상태 프로브 결과 — 서버 ID별 (상태, 도구 수)
    @State private var probes: [UUID: ProbeResult] = [:]
    @State private var isProbing = false
    @State private var editingServer: MCPServerConfig?

    struct ProbeResult {
        var ok: Bool
        var toolCount: Int
        var message: String
    }

    var body: some View {
        Form {
            Section("MCP 도구 — 베타 (v2.4)") {
                Toggle("도구 사용 활성화", isOn: $settings.mcpToolsEnabled)
                Text("연결된 MCP(stdio) 서버의 도구를 모델이 호출합니다. OpenAI 호환·Anthropic 모델만 지원하며, 기본 정책은 실행 전 매번 확인입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("서버 목록")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isProbing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("상태 확인") { Task { await probeAll() } }
                        .disabled(isProbing || store.servers.isEmpty)
                    Button {
                        editingServer = MCPServerConfig(name: "", command: "")
                    } label: {
                        Label("추가", systemImage: "plus")
                    }
                }
                if store.servers.isEmpty {
                    Text("등록된 서버가 없습니다. '추가'로 stdio MCP 서버를 등록하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.servers) { server in
                        serverRow(server)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(item: $editingServer) { config in
            MCPServerEditSheet(config: config)
        }
    }

    private func serverRow(_ server: MCPServerConfig) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(server))
                .frame(width: 8, height: 8)
                .help(statusText(server))
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name.isEmpty ? "(이름 없음)" : server.name)
                    .font(.system(size: 13, weight: .medium))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(server.command) \(server.args.joined(separator: " "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if server.transport == .http {
                    Text(server.url)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            }
            Spacer()
            if let probe = probes[server.id] {
                Text(probe.ok ? "도구 \(probe.toolCount)개" : probe.message)
                    .font(.caption2)
                    .foregroundStyle(probe.ok ? Color.green : Color.orange)
            }
            Toggle("", isOn: Binding(
                get: { server.isEnabled },
                set: { newValue in
                    var updated = server
                    updated.isEnabled = newValue
                    store.upsert(updated)
                    DebugLogger.shared.info("MCP", "서버 토글 '\(server.name)': \(newValue)")
                }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            Button("편집") { editingServer = server }
                .controlSize(.small)
            Button(role: .destructive) {
                store.remove(server.id)
                probes[server.id] = nil
                DebugLogger.shared.info("MCP", "서버 삭제: \(server.name)")
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ server: MCPServerConfig) -> Color {
        guard server.isEnabled else { return .gray }
        return probes[server.id]?.ok == true ? .green : (probes[server.id] != nil ? .orange : .gray)
    }

    private func statusText(_ server: MCPServerConfig) -> String {
        guard server.isEnabled else { return "비활성화" }
        guard let probe = probes[server.id] else { return "미확인" }
        return probe.message
    }

    /// 전체 활성 서버 프로브 — 연결 후 tools/list까지 확인
    @MainActor
    private func probeAll() async {
        isProbing = true
        defer { isProbing = false }
        DebugLogger.shared.info("MCP", "[SETTINGS] 상태 확인 시작 — 서버 \(store.servers.count)개")
        for server in store.servers where server.isEnabled {
            let connection = MCPConnectionFactory.make(config: server)
            await connection.connect()
            if case .ready = connection.state {
                probes[server.id] = ProbeResult(ok: true, toolCount: connection.tools.count,
                                                message: "연결됨 · 도구 \(connection.tools.count)개")
                DebugLogger.shared.info("MCP", "[SETTINGS] 프로브 성공 '\(server.name)': 도구 \(connection.tools.count)개")
                connection.disconnect()
            } else if case let .failed(reason) = connection.state {
                probes[server.id] = ProbeResult(ok: false, toolCount: 0, message: reason)
                DebugLogger.shared.warn("MCP", "[SETTINGS] 프로브 실패 '\(server.name)': \(reason)")
            }
        }
    }
}

// MARK: - 서버 추가·편집 시트

private struct MCPServerEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MCPServerStore.shared

    @State var config: MCPServerConfig
    @State private var argsText: String
    @State private var envText: String
    /// 시크릿 키 이름 목록 (줄바꿈 구분) — 값은 Keychain에만 저장
    @State private var secretKeysText: String
    @State private var secretDrafts: [String: String] = [:]
    /// HTTP 인증 토큰 입력값 — 저장 시 Keychain "AUTH_TOKEN"으로
    @State private var authTokenDraft: String = ""

    init(config: MCPServerConfig) {
        _config = State(initialValue: config)
        _argsText = State(initialValue: config.args.joined(separator: "\n"))
        _envText = State(initialValue: config.plainEnv.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"))
        _secretKeysText = State(initialValue: config.secretEnvKeys.joined(separator: "\n"))
    }

    /// 자주 쓰는 stdio 프리셋 — 클릭으로 명령어 채움
    private struct Preset: Identifiable {
        let id = UUID()
        let name: String
        let command: String
        let args: [String]
    }
    private let presets: [Preset] = [
        Preset(name: "filesystem", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", NSHomeDirectory()]),
        Preset(name: "memory", command: "npx", args: ["-y", "@modelcontextprotocol/server-memory"]),
        Preset(name: "fetch (uvx)", command: "uvx", args: ["mcp-server-fetch"]),
        Preset(name: "git", command: "uvx", args: ["mcp-server-git", "--repository", "."])
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text(store.servers.contains { $0.id == config.id } ? "MCP 서버 편집" : "MCP 서버 추가")
                .font(.headline)

            Form {
                TextField("이름", text: $config.name)
                Picker("전송 계층", selection: $config.transport) {
                    Text("stdio (로컬 프로세스)").tag(MCPTransportKind.stdio)
                    Text("HTTP (원격 서버)").tag(MCPTransportKind.http)
                }
                .pickerStyle(.radioGroup)

                if config.transport == .http {
                    TextField("엔드포인트 URL (예: https://example.com/mcp)", text: $config.url)
                    HStack {
                        TextField("인증 헤더명", text: $config.authHeaderName)
                            .frame(width: 150)
                        SecureField("인증 토큰 (입력 시 Keychain 저장)", text: $authTokenDraft)
                            .font(.system(size: 11, design: .monospaced))
                    }
                } else {
                    Menu("프리셋") {
                        ForEach(presets) { preset in
                            Button(preset.name) {
                                config.command = preset.command
                                argsText = preset.args.joined(separator: "\n")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("명령어 (예: npx, uvx, node)", text: $config.command)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("인자 (한 줄에 하나)").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $argsText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 52)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("환경변수 KEY=value (한 줄에 하나)").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $envText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 52)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("시크릿 환경변수 키 (한 줄에 하나 — 값은 Keychain 저장)")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $secretKeysText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 40)
                    }
                    secretFields
                }
            }

            HStack {
                Button("취소", role: .cancel) { dismiss() }
                Spacer()
                Button("저장") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding()
        .frame(width: 420)
    }

    @ViewBuilder
    private var secretFields: some View {
        let keys = parseLines(secretKeysText)
        if !keys.isEmpty {
            ForEach(keys, id: \.self) { key in
                HStack {
                    Text(key).font(.caption).frame(width: 110, alignment: .leading)
                    SecureField("값 입력 시 Keychain 갱신", text: Binding(
                        get: { secretDrafts[key] ?? "" },
                        set: { secretDrafts[key] = $0 }))
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
    }

    private var canSave: Bool {
        guard !config.name.isEmpty else { return false }
        if config.transport == .http {
            return !config.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !config.command.isEmpty
    }

    private func parseLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func parseEnv(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in parseLines(text) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...])
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    private func save() {
        var updated = config
        if updated.transport == .http {
            // HTTP — URL 필수, stdio 전용 입력 무시
            updated.url = updated.url.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            updated.args = parseLines(argsText)
            updated.plainEnv = parseEnv(envText)
        }
        let newSecretKeys = parseLines(secretKeysText)

        // 제거된 시크릿 정리 + 신규 값 Keychain 반영
        for removed in updated.secretEnvKeys where !newSecretKeys.contains(removed) {
            store.setSecret(serverID: updated.id, envKey: removed, value: "")
        }
        if updated.transport == .stdio {
            updated.secretEnvKeys = newSecretKeys
        }
        store.upsert(updated)
        for key in newSecretKeys where updated.transport == .stdio {
            if let value = secretDrafts[key], !value.isEmpty {
                store.setSecret(serverID: updated.id, envKey: key, value: value)
            }
        }
        // HTTP 인증 토큰 — 입력 시에만 갱신 (Keychain "AUTH_TOKEN")
        if updated.transport == .http, !authTokenDraft.isEmpty {
            store.setSecret(serverID: updated.id, envKey: MCPServerConfig.authTokenEnvKey, value: authTokenDraft)
        }
        DebugLogger.shared.info("MCP", "서버 저장: \(updated.name) (\(updated.transport.rawValue), 인자 \(updated.args.count))")
        dismiss()
    }
}

#Preview("MCP 설정") {
    MCPSettingsView()
        .padding()
        .frame(width: 480, height: 420)
}

/// 입력바 도구 셀렉터 (v2.4 T-121) — 도구 사용 토글 + 활성 서버 표시
struct MCPToolSelectorView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var store = MCPServerStore.shared

    private var enabledServers: [MCPServerConfig] {
        store.servers.filter(\.isEnabled)
    }

    var body: some View {
        Menu {
            Toggle("도구 사용", isOn: $settings.mcpToolsEnabled)
            Divider()
            if enabledServers.isEmpty {
                Text("등록된 서버 없음 — 설정에서 추가")
            } else {
                ForEach(enabledServers) { server in
                    Label(server.name, systemImage: "server.rack")
                }
            }
        } label: {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 14))
                .foregroundStyle(settings.mcpToolsEnabled ? Color.accentColor : Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 26)
        .help(settings.mcpToolsEnabled
              ? "MCP 도구 켜짐 — 활성 서버 \(enabledServers.count)개"
              : "MCP 도구 끄짐 — 클릭해서 사용 설정")
    }
}
