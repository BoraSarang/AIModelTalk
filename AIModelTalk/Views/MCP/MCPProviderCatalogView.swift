import SwiftUI

/// 원격 MCP 공급자 카탈로그 뷰 — 그리드/리스트로 탐색, 선택 시 연결 화면으로
struct MCPProviderCatalogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: MCPProviderTemplate.Category? = nil
    @State private var viewMode: ViewMode = .grid

    let onSelect: (MCPProviderTemplate) -> Void

    enum ViewMode { case grid, list }

    var filteredTemplates: [MCPProviderTemplate] {
        MCPProviderTemplate.search(searchText, category: selectedCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Text("MCP 공급자 연결")
                    .font(.headline)
                Spacer()
                Picker("", selection: $viewMode) {
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // 검색/필터 바
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("공급자 검색…", text: $searchText)
                    .textFieldStyle(.plain)

                Picker("카테고리", selection: $selectedCategory) {
                    Text("전체").tag(nil as MCPProviderTemplate.Category?)
                    ForEach(MCPProviderTemplate.Category.allCases, id: \.self) { cat in
                        Text(cat.displayName).tag(cat as MCPProviderTemplate.Category?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // 공급자 리스트
            ScrollView {
                if viewMode == .grid {
                    gridView
                } else {
                    listView
                }
            }
        }
        .frame(width: 600, height: 500)
    }

    private var gridView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
            ForEach(filteredTemplates) { template in
                CatalogProviderCard(template: template) {
                    onSelect(template)
                    dismiss()
                }
            }
        }
        .padding()
    }

    private var listView: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredTemplates) { template in
                CatalogProviderRow(template: template) {
                    onSelect(template)
                    dismiss()
                }
            }
        }
        .padding()
    }
}

/// 공급자 카드 (그리드 뷰용)
private struct CatalogProviderCard: View {
    let template: MCPProviderTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: template.icon)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    CatalogCategoryBadge(category: template.category)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    CatalogAuthModeBadge(mode: template.authMode)
                    Spacer()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 공급자 행 (리스트 뷰용)
private struct CatalogProviderRow: View {
    let template: MCPProviderTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                CatalogAuthModeBadge(mode: template.authMode)
                CatalogCategoryBadge(category: template.category)
                    .font(.caption2)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 인증 방식 뱃지
private struct CatalogAuthModeBadge: View {
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

/// 카테고리 뱃지
private struct CatalogCategoryBadge: View {
    let category: MCPProviderTemplate.Category

    var body: some View {
        Text(category.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.1))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }
}

/// 공급자 연결 화면 — OAuth 플로우 또는 API Key 입력
struct MCPProviderConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @ObservedObject private var store = MCPProviderStore.shared
    @ObservedObject private var manager = MCPProviderManager.shared

    let template: MCPProviderTemplate
    @State private var customURL: String = ""
    @State private var apiKey: String = ""
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var showSuccess = false

    init(template: MCPProviderTemplate) {
        self.template = template
        _customURL = State(initialValue: template.defaultURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 44, height: 44)
                    .background(theme.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(template.description)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                // 단계 표시기
                stepIndicator
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .foregroundStyle(theme.secondaryBorder)

            // 인증 방식별 UI
            Group {
                switch template.authMode {
                case .oauth21DCR:
                    oauthConnectView
                case .oauth21Manual:
                    oauthManualView
                case .apiKey:
                    apiKeyView
                case .selfHosted:
                    selfHostedView
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if let error = connectionError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.errorColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Spacer(minLength: 0)

            Divider()
                .foregroundStyle(theme.secondaryBorder)

            // 하단 버튼
            HStack {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if template.authMode == .selfHosted {
                    GradientButton(
                        title: "저장",
                        icon: "checkmark",
                        action: saveSelfHosted
                    )
                    .disabled(customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(theme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(width: 480, height: 380)
        .alert("연결 완료", isPresented: $showSuccess) {
            Button("확인") { dismiss() }
        } message: {
            Text("'\(template.name)' 공급자가 성공적으로 연결되었습니다.")
        }
    }

    // MARK: - 단계 표시기

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { step in
                Circle()
                    .fill(step == currentStep ? theme.accentColor : theme.tertiaryText.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private enum Step: CaseIterable {
        case select, auth, connect
    }

    private var currentStep: Step {
        if showSuccess { return .connect }
        if isConnecting { return .auth }
        return .select
    }

    // MARK: - OAuth 자동 연결 (DCR)

    private var oauthConnectView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundStyle(theme.accentColor)

            Text("OAuth 2.1 자동 연결")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.primaryText)

            Text("브라우저에서 \(template.name)에 로그인하고 권한을 승인하면 자동으로 연결됩니다.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let url = URL(string: template.docsURL) {
                Link("설정 가이드 보기", destination: url)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.accentColor)
            }

            if isConnecting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("브라우저 열기 중…")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
            } else {
                GradientButton(
                    title: "브라우저에서 연결",
                    icon: "safari",
                    action: { Task { await connectOAuth() } }
                )
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func connectOAuth() async {
        isConnecting = true
        connectionError = nil
        DebugLogger.shared.info("MCP", "[FEATURE] 공급자 연결 시작: \(template.name) (OAuth 2.1 DCR)")

        let config = MCPProviderConfiguration.fromTemplate(template, customURL: customURL.isEmpty ? nil : customURL)

        do {
            let scopes = template.scopes.isEmpty ? ["read"] : template.scopes
            let result = try await MCPOAuthService.authenticate(
                config: config,
                scopes: scopes,
                knownIssuer: template.issuer
            )

            DebugLogger.shared.debug("MCP", "[FEATURE] OAuth 성공 — 토큰 저장 시작")
            // 성공 시에만 공급자 저장
            store.upsert(config)

            // 토큰 저장
            store.setAccessToken(result.accessToken, for: config.id)
            if let rt = result.refreshToken {
                store.setRefreshToken(rt, for: config.id)
            }
            if let expiresIn = result.expiresIn {
                store.updateTokenExpiry(config.id, expiresIn: expiresIn)
            }
            if let clientId = result.clientId {
                var updated = config
                updated.clientId = clientId
                updated.clientSecret = result.clientSecret
                store.upsert(updated)
            }

            // 연결 테스트
            DebugLogger.shared.debug("MCP", "[FEATURE] 연결 테스트: \(config.displayName)")
            let connection = await MCPProviderManager.shared.connect(config)
            if case .ready = connection?.state {
                DebugLogger.shared.info("MCP", "[FEATURE] \(config.displayName) 연결 완료 — 도구 \(connection?.tools.count ?? 0)개")
                showSuccess = true
            } else if case let .failed(reason) = connection?.state {
                DebugLogger.shared.warn("MCP", "[FEATURE] \(config.displayName) 연결 테스트 실패: \(reason)")
                connectionError = "연결 테스트 실패: \(reason)"
            } else {
                connectionError = "준비 안 됨"
            }
        } catch {
            DebugLogger.shared.error("MCP", "[FEATURE] \(template.name) OAuth 실패: \(error.localizedDescription)")
            connectionError = error.localizedDescription
            // 실패하면 저장된 설정 제거 (있으면)
            store.removePendingIfNotConnected(config)
        }

        isConnecting = false
    }

    // MARK: - OAuth 수동 (Client ID/Secret 입력)

    private var oauthManualView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.ring")
                .font(.system(size: 44))
                .foregroundStyle(theme.accentColor)

            Text("OAuth 2.1 수동 설정")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.primaryText)

            Text("공급자 개발자 콘솔에서 OAuth 앱을 생성하고 Client ID/Secret을 발급받아 입력하세요.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // TODO: Client ID/Secret 입력 필드 + 리다이렉트 URI 안내
            Text("구현 예정: Client ID/Secret 입력")
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - API Key

    private var apiKeyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 44))
                .foregroundStyle(theme.accentColor)

            Text("API Key 입력")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.primaryText)

            Text("\(template.name) 대시보드에서 API Key를 발급받아 입력하세요.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 360)

            if let url = URL(string: template.docsURL) {
                Link("API Key 발급 가이드", destination: url)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.accentColor)
            }

            GradientButton(
                title: "저장 및 연결",
                icon: "checkmark",
                action: saveAPIKey
            )
            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(maxWidth: .infinity)
    }

    private func saveAPIKey() {
        DebugLogger.shared.info("MCP", "[FEATURE] API Key 연결 시작: \(template.name)")
        var config = MCPProviderConfiguration.fromTemplate(template, customURL: customURL.isEmpty ? nil : customURL)
        store.setAPIKey(apiKey, for: config.id)
        store.upsert(config)

        Task {
            let connection = await MCPProviderManager.shared.connect(config)
            if connection?.state == .ready {
                DebugLogger.shared.info("MCP", "[FEATURE] \(config.displayName) API Key 연결 완료")
                showSuccess = true
            } else {
                DebugLogger.shared.error("MCP", "[FEATURE] \(config.displayName) API Key 연결 실패: \(connection?.state ?? .idle)")
                connectionError = "연결 테스트 실패"
            }
        }
    }

    // MARK: - 자가 호스팅

    private var selfHostedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundStyle(theme.accentColor)

            Text("직접 호스팅 엔드포인트")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.primaryText)

            Text("Streamable HTTP MCP 엔드포인트 URL을 입력하세요.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            TextField("https://example.com/mcp", text: $customURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 360)

            Text("예: npx -y @modelcontextprotocol/server-filesystem ~/Documents")
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func saveSelfHosted() {
        DebugLogger.shared.info("MCP", "[FEATURE] 자가 호스팅 연결 시작: \(customURL)")
        let config = MCPProviderConfiguration.fromTemplate(template, customURL: customURL)
        store.upsert(config)

        Task {
            let connection = await MCPProviderManager.shared.connect(config)
            if case .ready = connection?.state {
                DebugLogger.shared.info("MCP", "[FEATURE] \(customURL) 연결 완료")
                showSuccess = true
            } else if case let .failed(reason) = connection?.state {
                DebugLogger.shared.error("MCP", "[FEATURE] \(customURL) 연결 실패: \(reason)")
                connectionError = "연결 실패: \(reason)"
            } else {
                connectionError = "준비 안 됨"
            }
        }
    }
}