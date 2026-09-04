import Foundation

/// MCP 공급자 인증 방식
enum MCPAuthMode: String, Codable, CaseIterable {
    case oauth21DCR = "oauth21_dcr"      // OAuth 2.1 + Dynamic Client Registration (자동)
    case oauth21Manual = "oauth21_manual" // OAuth 2.1 수동 (client_id/secret 입력 필요)
    case apiKey = "api_key"               // API Key (Bearer 토큰)
    case selfHosted = "self_hosted"       // 자가 호스팅 (URL만 입력)

    var displayName: String {
        switch self {
        case .oauth21DCR: return "OAuth 2.1 (자동 등록)"
        case .oauth21Manual: return "OAuth 2.1 (수동)"
        case .apiKey: return "API Key"
        case .selfHosted: return "자가 호스팅"
        }
    }

    var requiresBrowser: Bool {
        switch self {
        case .oauth21DCR, .oauth21Manual: return true
        case .apiKey, .selfHosted: return false
        }
    }

    /// 별칭 — 기존 코드 호환용
    var requiresBrowserAuth: Bool { requiresBrowser }
}

/// 잘 알려진 MCP 공급자 템플릿 (카탈로그)
struct MCPProviderTemplate: Identifiable, Codable, Hashable {
    let id: String                    // "linear", "notion", "github" 등
    let name: String                  // "Linear"
    let description: String
    let icon: String                  // SF Symbol 이름
    let defaultURL: String            // "https://mcp.linear.app"
    let authMode: MCPAuthMode
    let scopes: [String]              // 기본 요청 스코프
    let issuer: String?               // 알려진 인증 서버 issuer (자동 발견용 힌트)
    let docsURL: String               // 설정 가이드 URL
    let category: Category

    enum Category: String, Codable, CaseIterable {
        case productivity = "생산성"
        case development = "개발"
        case communication = "커뮤니케이션"
        case design = "디자인"
        case data = "데이터"
        case other = "기타"

        var displayName: String { rawValue }
    }

    // MARK: - 기본 공급자 카탈로그

    static let catalog: [MCPProviderTemplate] = [
        // 개발 도구
        MCPProviderTemplate(
            id: "linear",
            name: "Linear",
            description: "이슈/프로젝트 관리 — 티켓 조회, 생성, 업데이트",
            icon: "list.bullet.rectangle",
            defaultURL: "https://mcp.linear.app",
            authMode: .oauth21DCR,
            scopes: ["issues:read", "issues:write", "projects:read"],
            issuer: "https://linear.app",
            docsURL: "https://linear.app/docs/mcp",
            category: .development
        ),
        MCPProviderTemplate(
            id: "github",
            name: "GitHub",
            description: "리포지토리/이슈/PR 관리 — 코드 검색, 파일 읽기, PR 생성",
            icon: "chevron.left.forwardslash.chevron.right",
            defaultURL: "https://api.github.com/mcp",
            authMode: .oauth21DCR,
            scopes: ["repo", "read:org", "workflow"],
            issuer: "https://github.com",
            docsURL: "https://docs.github.com/en/mcp",
            category: .development
        ),
        MCPProviderTemplate(
            id: "gitlab",
            name: "GitLab",
            description: "프로젝트/이슈/MR 관리 — GitLab 셀프호스팅 포함",
            icon: "chevron.left.forwardslash.chevron.right",
            defaultURL: "https://gitlab.com/mcp",
            authMode: .oauth21DCR,
            scopes: ["api", "read_repository"],
            issuer: "https://gitlab.com",
            docsURL: "https://docs.gitlab.com/ee/user/mcp/",
            category: .development
        ),
        MCPProviderTemplate(
            id: "vercel",
            name: "Vercel",
            description: "배포/프로젝트/로그 관리 — 프리뷰 배포, 로그 조회",
            icon: "triangle.fill",
            defaultURL: "https://mcp.vercel.com",
            authMode: .oauth21DCR,
            scopes: ["read:deployments", "write:deployments"],
            issuer: "https://vercel.com",
            docsURL: "https://vercel.com/docs/mcp",
            category: .development
        ),

        // 생산성/문서
        MCPProviderTemplate(
            id: "notion",
            name: "Notion",
            description: "페이지/데이터베이스 검색·생성·업데이트 — 위키, 문서 관리",
            icon: "doc.richtext",
            defaultURL: "https://mcp.notion.com",
            authMode: .oauth21DCR,
            scopes: ["read:pages", "write:pages", "read:databases", "write:databases"],
            issuer: "https://api.notion.com",
            docsURL: "https://developers.notion.com/docs/mcp",
            category: .productivity
        ),
        MCPProviderTemplate(
            id: "slack",
            name: "Slack",
            description: "채널/메시지/파일 검색 — 팀 커뮤니케이션 조회",
            icon: "bubble.left.and.bubble.right",
            defaultURL: "https://slack.com/mcp",
            authMode: .oauth21DCR,
            scopes: ["channels:read", "chat:write", "files:read", "search:read"],
            issuer: "https://slack.com",
            docsURL: "https://api.slack.com/mcp",
            category: .communication
        ),
        MCPProviderTemplate(
            id: "atlassian",
            name: "Atlassian (Jira/Confluence)",
            description: "Jira 이슈/Confluence 페이지 관리 — 티켓, 위키",
            icon: "square.stack.3d.up",
            defaultURL: "https://mcp.atlassian.com",
            authMode: .oauth21DCR,
            scopes: ["read:jira-work", "write:jira-work", "read:confluence", "write:confluence"],
            issuer: "https://auth.atlassian.com",
            docsURL: "https://developer.atlassian.com/cloud/mcp/",
            category: .productivity
        ),

        // 데이터/인프라
        MCPProviderTemplate(
            id: "supabase",
            name: "Supabase",
            description: "PostgreSQL/스토리지/인증/에지 함수 관리",
            icon: "cylinder.split.1x2",
            defaultURL: "https://mcp.supabase.com",
            authMode: .oauth21DCR,
            scopes: ["projects:read", "database:read", "database:write"],
            issuer: "https://api.supabase.com",
            docsURL: "https://supabase.com/docs/mcp",
            category: .data
        ),
        MCPProviderTemplate(
            id: "cloudflare",
            name: "Cloudflare",
            description: "Workers/KV/D1/R2/페이지 관리 — 에지 컴퓨팅",
            icon: "cloud.fill",
            defaultURL: "https://mcp.cloudflare.com",
            authMode: .oauth21DCR,
            scopes: ["account:read", "zone:read", "workers:read", "workers:write"],
            issuer: "https://dash.cloudflare.com",
            docsURL: "https://developers.cloudflare.com/mcp/",
            category: .data
        ),
        MCPProviderTemplate(
            id: "sentry",
            name: "Sentry",
            description: "에러/성능 모니터링 — 이슈 조회, 릴리스 관리",
            icon: "exclamationmark.triangle",
            defaultURL: "https://mcp.sentry.io",
            authMode: .oauth21DCR,
            scopes: ["event:read", "project:read", "org:read"],
            issuer: "https://sentry.io",
            docsURL: "https://docs.sentry.io/mcp/",
            category: .development
        ),

        // 결제/비즈니스
        MCPProviderTemplate(
            id: "stripe",
            name: "Stripe",
            description: "결제/고객/구독/리포트 관리",
            icon: "creditcard.fill",
            defaultURL: "https://mcp.stripe.com",
            authMode: .oauth21DCR,
            scopes: ["read:charges", "read:customers", "read:subscriptions", "write:customers"],
            issuer: "https://connect.stripe.com",
            docsURL: "https://stripe.com/docs/mcp",
            category: .data
        ),

        // AI/기타
        MCPProviderTemplate(
            id: "openai",
            name: "OpenAI",
            description: "모델/파인튜닝/배치/파일 관리",
            icon: "brain",
            defaultURL: "https://api.openai.com/mcp",
            authMode: .apiKey,
            scopes: [],
            issuer: nil,
            docsURL: "https://platform.openai.com/docs/mcp",
            category: .other
        ),
        MCPProviderTemplate(
            id: "anthropic",
            name: "Anthropic",
            description: "Claude 모델/워크스페이스 관리",
            icon: "sparkles",
            defaultURL: "https://api.anthropic.com/mcp",
            authMode: .apiKey,
            scopes: [],
            issuer: nil,
            docsURL: "https://docs.anthropic.com/mcp",
            category: .other
        ),

        // 범용/자가 호스팅
        MCPProviderTemplate(
            id: "custom-http",
            name: "사용자 정의 HTTP/SSE",
            description: "임의의 Streamable HTTP MCP 엔드포인트 직접 연결",
            icon: "server.rack",
            defaultURL: "",
            authMode: .selfHosted,
            scopes: [],
            issuer: nil,
            docsURL: "https://docs.osaurus.ai/remote-mcp-providers",
            category: .other
        ),
        MCPProviderTemplate(
            id: "custom-stdio",
            name: "사용자 정의 stdio",
            description: "로컬 프로세스 실행 (npx, uvx, node 등) — filesystem, memory 등",
            icon: "terminal",
            defaultURL: "",
            authMode: .selfHosted,
            scopes: [],
            issuer: nil,
            docsURL: "https://docs.osaurus.ai/remote-mcp-providers",
            category: .other
        )
    ]

    /// 카테고리별 그룹화
    static var byCategory: [Category: [MCPProviderTemplate]] {
        Dictionary(grouping: catalog, by: \.category)
    }

    /// 검색/필터
    static func search(_ query: String, category: Category? = nil) -> [MCPProviderTemplate] {
        catalog.filter { template in
            let matchesQuery = query.isEmpty ||
                template.name.localizedCaseInsensitiveContains(query) ||
                template.description.localizedCaseInsensitiveContains(query) ||
                template.id.localizedCaseInsensitiveContains(query)
            let matchesCategory = category == nil || template.category == category
            return matchesQuery && matchesCategory
        }
    }
}