import Foundation

/// 세션별 병렬 스트리밍을 관리하는 전용 매니저 (v3.0 T-002)
///
/// 기존 ChatViewModel은 단일 `currentTask`/`streamingMessageID`로 한 번에 하나의
/// 세션만 스트리밍할 수 있었다. Split Chat(병렬 대화)을 지원하려면 세션 키 기준의
/// 작업 수명주기 관리가 필요하다.
///
/// - `start(sessionID:operation:)` — 세션에 작업 등록, 기존 진행 중 작업은 취소 후 재시작
/// - `stop(sessionID:)` — 특정 세션 스트리밍 중지
/// - `stopAll()` — 전체 스트리밍 중지 (앱 종료/전역 중지)
/// - `isStreaming(sessionID:)` — 세션 스트리밍 여부 조회
@MainActor
final class StreamManager {
    static let shared = StreamManager()

    /// 세션별 실행 중인 스트리밍 작업
    private var tasks: [UUID: Task<Void, Never>] = [:]

    /// 특정 세션에 스트리밍 작업 등록. 동일 세션의 기존 작업이 있으면 취소 후 덮어쓴다.
    @discardableResult
    func start(_ sessionID: UUID, operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        stop(sessionID)
        let task = Task { @MainActor in
            await operation()
        }
        tasks[sessionID] = task
        return task
    }

    /// 특정 세션의 스트리밍 작업을 취소하고 해제한다.
    func stop(_ sessionID: UUID) {
        guard let task = tasks.removeValue(forKey: sessionID) else { return }
        task.cancel()
    }

    /// 진행 중인 모든 세션 스트리밍을 중지한다.
    func stopAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }

    /// 특정 세션 스트리밍이 진행 중인지 여부
    func isStreaming(_ sessionID: UUID) -> Bool {
        tasks[sessionID] != nil && !(tasks[sessionID]?.isCancelled ?? true)
    }

    /// 진행 중인 스트리밍 세션 ID 목록
    var activeSessions: [UUID] {
        Array(tasks.keys)
    }
}
