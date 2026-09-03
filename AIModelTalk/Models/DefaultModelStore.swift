import Foundation

/// 새 대화 시작 모델로 사용할 기본 모델 저장소 (v1.7.3 T-66)
/// UserDefaults를 주입받아 테스트 격리가 가능하다 (SkillFlagStore와 동일 패턴).
struct DefaultModelStore {
    let defaults: UserDefaults
    private let key = "appDefaultModel"

    var model: AIModel? {
        get {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(AIModel.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
