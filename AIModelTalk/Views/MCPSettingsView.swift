import SwiftUI

// MARK: - MCP 서버 관리 설정 화면 (v2.4 T-121, v2.5 원격 MCP 공급자 추가)

/// MCP 삭제 확인 대화상자 대상 — Identifiable 단일 alert용
enum MCPDeletionTarget: Identifiable {
    case provider(MCPProviderConfiguration)
    case server(MCPServerConfig)

    var id: String {
        switch self {
        case .provider(let p): return "provider-\(p.id)"
        case .server(let s): return "server-\(s.id)"
        }
    }
}

struct MCPSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var stdioStore = MCPServerStore.shared
    @ObservedObject private var remoteStore = MCPProviderStore.shared
    @ObservedObject private var manager = MCPProviderManager.shared
    @Environment(\.theme) private var theme

    /// stdio 서버 상태 프로브 결과
    @State private var stdioProbes: [UUID: ProbeResult] = [:]
    /// 원격 공급자 상태 프로브 결과
    @State private var remoteProbes: [UUID: RemoteProbeResult] = [:]
    @State private var isProbing = false
    @State private var editingServer: MCPServerConfig?
    @State private var showProviderCatalog = false
    @State private var editingRemoteProvider: MCPProviderConfiguration?
    /// 삭제 확인 대화상자 대상 (공급자/stdio 서버) — 단일 alert로 처리 (macOS 동일 뷰 다중 alert 충돌 회피)
    @State private var confirmDeletion: MCPDeletionTarget?

    struct ProbeResult {
        var ok: Bool
        var toolCount: Int
        var message: String
    }

    struct RemoteProbeResult {
        var ok: Bool
        var toolCount: Int
        var message: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space12) {
                ThemedSettingsCard { remoteSection }

                ThemedSettingsCard("MCP 도구 — 베타 (v2.4)") { toolsSection }

                ThemedSettingsCard("로컬 MCP 서버 (stdio)") { stdioSection }
            }
            .padding(theme.space16)
        }
        .sheet(item: $editingServer) { config in
            MCPServerEditSheet(config: config)
        }
        .sheet(isPresented: $showProviderCatalog) {
            MCPProviderCatalogView { template in
                showProviderCatalog = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    editingRemoteProvider = MCPProviderConfiguration.fromTemplate(template)
                }
            }
        }
        .sheet(item: $editingRemoteProvider) { provider in
            MCPProviderConnectView(template: provider.template ?? MCPProviderTemplate.catalog.first!)
                .onDisappear {
                    if provider.isConnected {
                        Task { await probeRemote(provider) }
                    }
                }
        }
        .alert(item: $confirmDeletion) { target in
            switch target {
            case .provider(let provider):
                return Alert(
                    title: Text("'\(provider.displayName)' 공급자 삭제"),
                    message: Text("연결 정보와 설정이 제거됩니다. 되돌릴 수 없습니다."),
                    primaryButton: .destructive(Text("삭제")) {
                        remoteStore.remove(provider.id)
                        remoteProbes[provider.id] = nil
                        manager.disconnect(provider.id)
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            case .server(let server):
                return Alert(
                    title: Text("'\(server.name)' 서버 삭제"),
                    message: Text("등록된 MCP 서버 설정이 제거됩니다. 되돌릴 수 없습니다."),
                    primaryButton: .destructive(Text("삭제")) {
                        stdioStore.remove(server.id)
                        stdioProbes[server.id] = nil
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            }
        }
    }

    // MARK: - 원격 공급자 섹션

    @ViewBuilder
    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: theme.space10) {
            HStack {
                Label("원격 MCP 공급자", systemImage: "externaldrive")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                if !remoteStore.providers.isEmpty {
                    Text(remoteSummary)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .monospacedDigit()
                }
                Spacer()
                if isProbing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("상태 확인") { Task { await probeAll() } }
                    .disabled(isProbing || remoteStore.providers.isEmpty)
                Button {
                    showProviderCatalog = true
                } label: {
                    Label("공급자 연결…", systemImage: "plus")
                }
            }

            if remoteStore.providers.isEmpty {
                EmptyStateView.noProviders(onConnect: { showProviderCatalog = true }, compact: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, theme.space8)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(Array(remoteStore.providers.enumerated()), id: \.element.id) { index, provider in
                        ProviderCard(
                            report: reportForProvider(provider),
                            animationIndex: index,
                            isTesting: false,
                            onEdit: { editingRemoteProvider = provider },
                            onDelete: { confirmDeletion = .provider(provider) },
                            onConnect: { Task { await probeRemote(provider) } },
                            onDisconnect: { manager.disconnect(provider.id) },
                            onTest: { Task { await probeRemote(provider) } },
                            onCopyDiagnostics: { copyDiagnostics(for: provider) },
                            onToggleEnabled: { newValue in
                                var updated = provider
                                updated.isEnabled = newValue
                                remoteStore.upsert(updated)
                                if !newValue { manager.disconnect(provider.id) }
                            },
                            onSignIn: { editingRemoteProvider = provider },
                            onSaveBearerToken: { token in
                                remoteStore.setAccessToken(token, for: provider.id)
                            }
                        )
                    }
                }
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: theme.space8) {
            Toggle("도구 사용 활성화", isOn: $settings.mcpToolsEnabled)
                .toggleStyle(.switch)
            ThemedSettingsCaption("연결된 MCP(stdio/원격) 서버의 도구를 모델이 호출합니다. OpenAI 호환·Anthropic 모델만 지원하며, 기본 정책은 실행 전 매번 확인입니다.")
        }
    }

    private var stdioSection: some View {
        VStack(alignment: .leading, spacing: theme.space10) {
            HStack {
                ThemedSettingsCaption("서버 목록")
                Spacer()
                Button {
                    editingServer = MCPServerConfig(name: "", command: "")
                } label: {
                    Label("추가", systemImage: "plus")
                }
            }
            if stdioStore.servers.isEmpty {
                ThemedSettingsCaption("등록된 로컬 서버가 없습니다. '추가'로 stdio MCP 서버를 등록하세요.")
            } else {
                ForEach(stdioStore.servers) { server in
                    serverRow(server)
                }
            }
        }
    }

    // MARK: - Helper

    /// 헤더줄 요약 — 기존 별도 "공급자 상태/활성 도구/전체 공급자" 카드(T-325) 대체
    private var remoteSummary: String {
        let totalProviders = remoteStore.providers.count
        let enabledProviders = remoteStore.providers.filter(\.isEnabled).count
        let connectedCount = remoteStore.providers.filter { remoteProbes[$0.id]?.ok == true }.count
        let totalTools = remoteProbes.values.filter(\.ok).reduce(0) { $0 + $1.toolCount }
        return "\(connectedCount)/\(enabledProviders) 연결됨 · 도구 \(totalTools)개 · 전체 \(totalProviders)"
    }

    private func reportForProvider(_ provider: MCPProviderConfiguration) -> MCPServerHubProviderReport {
        let probe = remoteProbes[provider.id]
        let diagnostics: MCPProviderDiagnostics? = probe.map { probe in
            MCPProviderDiagnostics(
                status: probe.ok ? .connected : .error,
                toolCount: probe.toolCount,
                message: probe.message
            )
        }
        return MCPServerHubProviderReport(id: provider.id, provider: provider, diagnostics: diagnostics)
    }

    private func copyDiagnostics(for provider: MCPProviderConfiguration) {
        let probe = remoteProbes[provider.id]
        let text = """
        공급자: \(provider.displayName)
        URL: \(provider.url)
        인증: \(provider.authMode.displayName)
        상태: \(probe.map { $0.ok ? "연결됨" : "오류: \($0.message)" } ?? "미확인")
        도구 수: \(probe?.toolCount ?? 0)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - 기존 stdio 서버 행 (기존 코드 유지)

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
            if let probe = stdioProbes[server.id] {
                Text(probe.ok ? "도구 \(probe.toolCount)개" : probe.message)
                    .font(.caption2)
                    .foregroundStyle(probe.ok ? Color.green : Color.orange)
            }
            Toggle("", isOn: Binding(
                get: { server.isEnabled },
                set: { newValue in
                    var updated = server
                    updated.isEnabled = newValue
                    stdioStore.upsert(updated)
                }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            Button("편집") { editingServer = server }
                .controlSize(.small)
            Button(role: .destructive) {
                confirmDeletion = .server(server)
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
            .help("삭제")
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ server: MCPServerConfig) -> Color {
        guard server.isEnabled else { return .gray }
        return stdioProbes[server.id]?.ok == true ? .green : (stdioProbes[server.id] != nil ? .orange : .gray)
    }

    private func statusText(_ server: MCPServerConfig) -> String {
        guard server.isEnabled else { return "비활성화" }
        guard let probe = stdioProbes[server.id] else { return "미확인" }
        return probe.message
    }

    // MARK: - 프로브

    /// 전체 프로브 (원격 + stdio)
    @MainActor
    private func probeAll() async {
        isProbing = true
        defer { isProbing = false }
        await probeAllRemote()
        await probeAllStdio()
    }

    @MainActor
    private func probeAllRemote() async {
        DebugLogger.shared.info("MCP", "[SETTINGS] 원격 공급자 상태 확인 시작 — \(remoteStore.providers.count)개")
        for provider in remoteStore.providers where provider.isEnabled {
            await probeRemote(provider)
        }
    }

    @MainActor
    private func probeRemote(_ provider: MCPProviderConfiguration) async {
        let connection = await manager.connect(provider)
        if case .ready = connection?.state {
            remoteProbes[provider.id] = RemoteProbeResult(ok: true, toolCount: connection?.tools.count ?? 0,
                                                          message: "연결됨 · 도구 \(connection?.tools.count ?? 0)개")
            DebugLogger.shared.info("MCP", "[SETTINGS] 원격 프로브 성공 '\(provider.displayName)': 도구 \(connection?.tools.count ?? 0)개")
        } else if case let .failed(reason) = connection?.state {
            remoteProbes[provider.id] = RemoteProbeResult(ok: false, toolCount: 0, message: reason)
            DebugLogger.shared.warn("MCP", "[SETTINGS] 원격 프로브 실패 '\(provider.displayName)': \(reason)")
        }
    }

    @MainActor
    private func probeAllStdio() async {
        DebugLogger.shared.info("MCP", "[SETTINGS] stdio 상태 확인 시작 — 서버 \(stdioStore.servers.count)개")
        for server in stdioStore.servers where server.isEnabled {
            let connection = MCPConnectionFactory.make(config: server)
            await connection.connect()
            if case .ready = connection.state {
                stdioProbes[server.id] = ProbeResult(ok: true, toolCount: connection.tools.count,
                                                     message: "연결됨 · 도구 \(connection.tools.count)개")
                DebugLogger.shared.info("MCP", "[SETTINGS] 프로브 성공 '\(server.name)': 도구 \(connection.tools.count)개")
                connection.disconnect()
            } else if case let .failed(reason) = connection.state {
                stdioProbes[server.id] = ProbeResult(ok: false, toolCount: 0, message: reason)
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
        Preset(name: "wigolo (웹 검색)", command: "npx", args: ["-y", "wigolo"]),
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
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("명령어").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("예: npx, uvx, node").font(.caption).foregroundStyle(.tertiary)
                        }
                        TextField("npx", text: $config.command)
                    }
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

// MARK: - 공유 뱃지 뷰 (MCPSettingsView, MCPProviderCatalogView에서 사용)

private struct SettingsAuthModeBadge: View {
    let mode: MCPAuthMode

    var body: some View {
        Text(mode.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch mode {
        case .oauth21DCR: return Color.blue.opacity(0.15)
        case .oauth21Manual: return Color.purple.opacity(0.15)
        case .apiKey: return Color.green.opacity(0.15)
        case .selfHosted: return Color.gray.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch mode {
        case .oauth21DCR: return .blue
        case .oauth21Manual: return .purple
        case .apiKey: return .green
        case .selfHosted: return .gray
        }
    }
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