import Foundation

/// 스킬 숨김·기본 플래그 저장소 (v1.7 T-55~56)
/// UserDefaults를 주입받아 테스트 격리가 가능하다.
struct SkillFlagStore {
    let defaults: UserDefaults

    /// 피커에서 숨긴 스킬 ID 목록
    var hiddenIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "hiddenSkillIDs") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "hiddenSkillIDs") }
    }

    /// 새 대화에 자동 적용되는 기본 스킬 ID 목록
    var defaultIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "defaultSkillIDs") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "defaultSkillIDs") }
    }
}
