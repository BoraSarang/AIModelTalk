import SwiftUI
import AppKit

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
    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    @State private var customAuthEndpoint: String = ""
    @State private var customTokenEndpoint: String = ""
    @State private var oauthMode: MCPAuthMode
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var showSuccess = false

    init(template: MCPProviderTemplate) {
        self.template = template
        _customURL = State(initialValue: template.defaultURL)
        _oauthMode = State(initialValue: template.authMode)
        _customAuthEndpoint = State(initialValue: template.authorizationEndpoint ?? "")
        _customTokenEndpoint = State(initialValue: template.tokenEndpoint ?? "")
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

            // 인증 방식별 UI — OAuth 템플릿은 자동/수동 선택 (T-333)
            Group {
                switch template.authMode {
                case .oauth21DCR, .oauth21Manual:
                    oauthModeSection
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
        .frame(width: 480, height: frameHeight)
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

    /// OAuth 자동/수동 선택 래퍼 (T-333) — 기본값은 템플릿 권장 방식
    private var oauthModeSection: some View {
        VStack(spacing: 12) {
            Picker("", selection: $oauthMode) {
                Text("자동").tag(MCPAuthMode.oauth21DCR)
                Text("수동").tag(MCPAuthMode.oauth21Manual)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 220)
            if oauthMode == .oauth21Manual {
                oauthManualView
            } else {
                oauthConnectView
            }
        }
    }

    private var frameHeight: CGFloat {
        switch template.authMode {
        case .apiKey, .selfHosted:
            return 380
        case .oauth21DCR, .oauth21Manual:
            return oauthMode == .oauth21Manual ? 640 : 420
        }
    }

    private var currentStep: Step {
        if showSuccess { return .connect }
        if isConnecting { return .auth }
        return .select
    }

    /// URL 비교용 정규화 — 공백 제거 + 후행 슬래시 제거 (T-326)
    private static func normalizedURL(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
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
        var config = MCPProviderConfiguration.fromTemplate(template, customURL: customURL.isEmpty ? nil : customURL)
        config.authMode = .oauth21DCR
        applyDedupIfNeeded(&config)
        await performOAuth(
            config: config,
            authorizationEndpoint: nil,
            tokenEndpoint: nil,
            mode: "OAuth 2.1 DCR"
        )
    }

    /// 수동 OAuth — 사용자가 발급받은 Client ID/Secret으로 인가 (전 공급자, T-333)
    /// 엔드포인트는 템플릿 내장값 프리필 + 직접 수정 가능 (미지원 공급자용)
    private func connectOAuthManual() async {
        var config = MCPProviderConfiguration.fromTemplate(template, customURL: customURL.isEmpty ? nil : customURL)
        config.authMode = .oauth21Manual
        config.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        config.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoints = MCPOAuthService.resolveEndpoints(
            template: template,
            customAuthorizationEndpoint: customAuthEndpoint,
            customTokenEndpoint: customTokenEndpoint
        )
        config.customAuthorizationEndpoint = nonEmptyOrNil(customAuthEndpoint)
        config.customTokenEndpoint = nonEmptyOrNil(customTokenEndpoint)
        applyDedupIfNeeded(&config)
        await performOAuth(
            config: config,
            authorizationEndpoint: endpoints.authorizationEndpoint,
            tokenEndpoint: endpoints.tokenEndpoint,
            mode: "OAuth 2.1 수동"
        )
    }

    private func nonEmptyOrNil(_ value: String) -> String? {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 수동 연결 가능 여부 — Client ID/Secret + 양 엔드포인트(템플릿 또는 입력) 필요
    private var canConnectManual: Bool {
        let endpoints = MCPOAuthService.resolveEndpoints(
            template: template,
            customAuthorizationEndpoint: customAuthEndpoint,
            customTokenEndpoint: customTokenEndpoint
        )
        return !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(endpoints.authorizationEndpoint?.isEmpty ?? true)
            && !(endpoints.tokenEndpoint?.isEmpty ?? true)
    }

    /// 동일 공급자(templateID + 정규화 url)가 이미 등록되어 있으면 기존 항목에 갱신 (T-326)
    private func applyDedupIfNeeded(_ config: inout MCPProviderConfiguration) {
        if let existing = store.providers.first(where: {
            $0.templateID == template.id && Self.normalizedURL($0.url) == Self.normalizedURL(config.url)
        }) {
            DebugLogger.shared.info("MCP", "[FEATURE] 동일 공급자 발견 — 기존 항목 갱신: \(existing.id.uuidString)")
            config.id = existing.id
            config.isEnabled = existing.isEnabled
        }
    }

    /// 공통 OAuth 실행 — 자동(DCR)/수동 모두 이 경로로
    private func performOAuth(
        config: MCPProviderConfiguration,
        authorizationEndpoint: String?,
        tokenEndpoint: String?,
        mode: String
    ) async {
        isConnecting = true
        connectionError = nil
        DebugLogger.shared.info("MCP", "[FEATURE] 공급자 연결 시작: \(template.name) (\(mode))")

        let scopes = template.scopes.isEmpty ? ["read"] : template.scopes

        do {
            let result = try await MCPOAuthService.authenticate(
                config: config,
                scopes: scopes,
                knownIssuer: template.issuer,
                authorizationEndpoint: authorizationEndpoint,
                tokenEndpoint: tokenEndpoint
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
        VStack(spacing: 14) {
            Image(systemName: "key.ring")
                .font(.system(size: 36))
                .foregroundStyle(theme.accentColor)

            Text("OAuth 2.1 수동 설정")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.primaryText)

            Text("""
            \(template.name) 개발자 콘솔에서 OAuth 앱을 생성하고 아래 redirect URI를 등록한 뒤 \
            Client ID/Secret을 발급받아 입력하세요.
            """)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // 리다이렉트 URI (콘솔 등록용) + 복사
            HStack(spacing: 8) {
                Text(OAuthLoopbackServer.manualCallbackURL.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(theme.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.secondaryBorder, lineWidth: 1)
                    )
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(OAuthLoopbackServer.manualCallbackURL.absoluteString, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 8) {
                TextField("Client ID", text: $clientId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                SecureField("Client Secret", text: $clientSecret)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                TextField("Authorize URL (비우면 템플릿 기본값)", text: $customAuthEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                TextField("Token URL (비우면 템플릿 기본값)", text: $customTokenEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                if template.authorizationEndpoint == nil && template.tokenEndpoint == nil {
                    Text("이 공급자는 기본 엔드포인트가 없습니다 — 개발자 콘솔의 OAuth 정보를 직접 입력하세요.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 380)

            HStack(spacing: 12) {
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
                        action: { Task { await connectOAuthManual() } }
                    )
                    .disabled(!canConnectManual)
                }
            }
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