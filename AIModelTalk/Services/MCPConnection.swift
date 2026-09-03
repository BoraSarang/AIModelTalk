import Foundation

/// 대기 응답 레지스트리 — id → continuation (락 보호, 타임아웃 워커와 응답 경쟁 안전)
private final class MCPResponseRegistry {
    struct Pending {
        let continuation: CheckedContinuation<MCPProtocol.Inbound, Error>
        let timeoutItem: DispatchWorkItem
    }

    private let lock = NSLock()
    private var map: [Int: Pending] = [:]

    func register(_ pending: Pending, forKey id: Int) {
        lock.lock()
        map[id] = pending
        lock.unlock()
    }

    /// 등록 해제 + 항목 반환 — 이미 해제됐으면 nil (타임아웃이 먼저 처리한 경우)
    func remove(forKey id: Int) -> Pending? {
        lock.lock()
        defer { lock.unlock() }
        return map.removeValue(forKey: id)
    }

    func removeAll() -> [Pending] {
        lock.lock()
        defer { lock.unlock() }
        let all = Array(map.values)
        map.removeAll()
        return all
    }
}

/// MCP stdio 연결 — 서버 프로세스 관리 + JSON-RPC 요청-응답 상관 (v2.4 T-119)
/// 상태 머신: idle → connecting → ready / failed(사유), disconnect → idle
@MainActor
final class MCPConnection: ObservableObject {

    enum State: Equatable {
        case idle
        case connecting
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var tools: [MCPTool] = []
    @Published private(set) var logLines: [String] = []

    private let config: MCPServerConfig
    private let clientName = "AIModelTalk"
    private let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.4"

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var nextID = 1
    private let registry = MCPResponseRegistry()

    init(config: MCPServerConfig) {
        self.config = config
    }

    // MARK: - 생명주기

    func connect() async {
        guard state != .ready, state != .connecting else { return }
        state = .connecting
        appendLog("[FEATURE] 서버 연결 시작: \(config.command) \(config.args.joined(separator: " "))")
        do {
            try launchProcess()
            let id = issueID()
            stdinHandle?.write(MCPProtocol.initializeRequest(id: id, clientName: clientName, clientVersion: clientVersion))
            _ = try await awaitResponse(id: id, timeout: 20)
            stdinHandle?.write(MCPProtocol.initializedNotification())

            let listID = issueID()
            stdinHandle?.write(MCPProtocol.toolsListRequest(id: listID))
            let listResponse = try await awaitResponse(id: listID, timeout: 15)
            if case let .response(_, result) = listResponse {
                tools = MCPProtocol.parseTools(fromResult: result)
            }
            state = .ready
            DebugLogger.shared.info("MCP", "[FEATURE] 서버 연결 완료: '\(config.name)' 도구 \(tools.count)개")
        } catch {
            teardownProcess()
            state = .failed("연결 실패: \(error.localizedDescription)")
            DebugLogger.shared.error("MCP", "E-MAC-NET-1003 서버 연결 실패 '\(config.name)': \(error.localizedDescription)")
        }
    }

    func disconnect() {
        teardownProcess()
        tools = []
        state = .idle
        appendLog("연결 종료")
    }

    /// 수동 재시작 — failed/idle에서 호출
    func restart() async {
        disconnect()
        await connect()
    }

    // MARK: - 도구 호출

    /// 도구 실행 — 미연결이면 먼저 connect. 성공 시 결과 텍스트, 실패 시 throw.
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        if state != .ready {
            await connect()
            guard case .ready = state else {
                throw MCPProtocol.ProtocolError.serverError("서버 미연결 — 도구 호출 불가")
            }
        }
        let id = issueID()
        stdinHandle?.write(try MCPProtocol.toolsCallRequest(id: id, name: name, arguments: arguments))
        let response = try await awaitResponse(id: id, timeout: 60)
        switch response {
        case let .response(_, result):
            let outcome = MCPProtocol.parseCallResult(fromResult: result)
            if outcome.isError {
                appendLog("도구 '\(name)' 오류: \(outcome.text)")
                throw MCPProtocol.ProtocolError.serverError(outcome.text)
            }
            appendLog("도구 '\(name)' 성공 (\(outcome.text.count)자)")
            return outcome.text
        case let .error(_, message):
            throw MCPProtocol.ProtocolError.serverError(message)
        case .notification:
            throw MCPProtocol.ProtocolError.serverError("예상치 못한 알림 수신")
        }
    }

    // MARK: - 프로세스

    private func launchProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.command)
        process.arguments = config.args
        var env = ProcessInfo.processInfo.environment.merging(config.resolvedEnv()) { current, _ in current }
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:" + (env["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? "")
        process.environment = env

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        // 비정상 종료 감지 → ready였다면 failed 전이
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .ready || self.state == .connecting else { return }
                self.teardownProcess()
                self.state = .failed("서버 프로세스 종료됨 (exit \(process.terminationStatus))")
                self.appendLog("프로세스 종료 (exit \(process.terminationStatus))")
            }
        }

        try process.run()
        self.process = process
        stdinHandle = stdin.fileHandleForWriting

        startReadLoop(stdout.fileHandleForReading, isError: false)
        startReadLoop(stderr.fileHandleForReading, isError: true)
    }

    private func startReadLoop(_ handle: FileHandle, isError: Bool) {
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else {
                fh.readabilityHandler = nil
                return
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor [weak self] in
                self?.handleChunk(text, isError: isError)
            }
        }
    }

    private var stdoutBuffer = ""
    private var stderrBuffer = ""

    private func handleChunk(_ chunk: String, isError: Bool) {
        if isError {
            stderrBuffer += chunk
            let lines = drainLines(&stderrBuffer)
            for line in lines where !line.isEmpty { appendLog("[stderr] \(line)") }
            return
        }
        stdoutBuffer += chunk
        for line in drainLines(&stdoutBuffer) {
            guard let inbound = MCPProtocol.parse(line: line) else { continue }
            switch inbound {
            case let .response(id, result):
                resumePending(id: id, with: .response(id: id, result: result))
            case let .error(id, message):
                if let id { resumePending(id: id, with: .error(id: id, message: message)) } else { appendLog("[error] \(message)") }
            case let .notification(method):
                appendLog("[알림] \(method)")
            }
        }
    }

    private func drainLines(_ buffer: inout String) -> [String] {
        guard buffer.contains("\n") else { return [] }
        var lines: [String] = []
        while let idx = buffer.firstIndex(of: "\n") {
            lines.append(String(buffer[..<idx]))
            buffer.removeSubrange(...idx)
        }
        return lines
    }

    // MARK: - 응답 레지스트리

    private func issueID() -> Int {
        let id = nextID
        nextID += 1
        return id
    }

    /// 응답 대기 — 타임아웃 워커가 백업 해제 (레지스트리 내부 락으로 경쟁 안전)
    private func awaitResponse(id: Int, timeout: TimeInterval) async throws -> MCPProtocol.Inbound {
        try await withCheckedThrowingContinuation { continuation in
            let registry = self.registry
            let timeoutItem = DispatchWorkItem {
                if let pending = registry.remove(forKey: id) {
                    pending.continuation.resume(
                        throwing: MCPProtocol.ProtocolError.serverError("응답 시간 초과 (\(Int(timeout))초)"))
                    Task { @MainActor [weak self] in
                        self?.appendLog("요청 #\(id) 시간 초과")
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            registry.register(
                MCPResponseRegistry.Pending(continuation: continuation, timeoutItem: timeoutItem),
                forKey: id)
        }
    }

    private func resumePending(id: Int, with inbound: MCPProtocol.Inbound) {
        if let pending = registry.remove(forKey: id) {
            pending.timeoutItem.cancel()
            pending.continuation.resume(returning: inbound)
        }
    }

    private func teardownProcess() {
        // 대기 중인 모든 응답 실패 처리 — 유실 방지
        for pending in registry.removeAll() {
            pending.timeoutItem.cancel()
            pending.continuation.resume(throwing: MCPProtocol.ProtocolError.serverError("연결 종료됨"))
        }

        stdinHandle?.closeFile()
        stdinHandle = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdoutBuffer = ""
        stderrBuffer = ""
    }

    private func appendLog(_ line: String) {
        logLines.append("[\(Self.timeStamp())] \(line)")
        if logLines.count > 200 { logLines.removeFirst(logLines.count - 200) }
    }

    private static func timeStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
