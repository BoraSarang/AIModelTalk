import Foundation
import SwiftData

final class PersistenceController {
    static let shared = PersistenceController()

    let modelContainer: ModelContainer
    let modelContext: ModelContext

    private init() {
        let schema = Schema([ChatSessionEntity.self, ChatMessageEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            modelContext = ModelContext(modelContainer)
        } catch {
            fatalError("SwiftData 컨테이너 초기화 실패: \(error)")
        }
    }

    // MARK: - 마이그레이션: UserDefaults → SwiftData

    /// 기존 UserDefaults "chatSessions" 데이터를 SwiftData로 자동 이전
    /// 성공/실패 여부 반환. 이미 이전 완료 시 false 반환
    @discardableResult
    static func migrateFromUserDefaultsIfNeeded() -> Bool {
        let key = "chatSessions"
        guard let data = UserDefaults.standard.data(forKey: key) else {
            DebugLogger.shared.debug("PERSIST", "UserDefaults에 마이그레이션 대상 없음")
            return false
        }

        DebugLogger.shared.info("PERSIST", "UserDefaults 데이터 발견: \(data.count)바이트. 마이그레이션 시도...")

        do {
            let legacy = try JSONDecoder().decode([ChatSession].self, from: data)
            let context = shared.modelContext

            for session in legacy {
                let entity = ChatSessionEntity(from: session)
                context.insert(entity)
            }
            try context.save()

            // 이전 완료 표시
            UserDefaults.standard.removeObject(forKey: key)
            DebugLogger.shared.info("PERSIST", "UserDefaults → SwiftData 마이그레이션 완료 (\(legacy.count)개 세션)")
            return true
        } catch {
            DebugLogger.shared.error("PERSIST", "[E-MAC-STR-1001] 마이그레이션 실패: \(error.localizedDescription)")
            DebugLogger.shared.debug("PERSIST", "마이그레이션 실패 상세: \(error)")
            // 손상된 데이터 제거하여 반복 에러 방지
            UserDefaults.standard.removeObject(forKey: key)
            DebugLogger.shared.warn("PERSIST", "손상된 UserDefaults 데이터 제거 완료")
            return false
        }
    }
}
