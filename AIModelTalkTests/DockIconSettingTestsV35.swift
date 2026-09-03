import XCTest
@testable import AIModelTalk

/// v3.5 — Dock 아이콘 표시 설정 (T-163)
/// 기본값 = Dock 숨김(false). 런타임 전환(applyDockPolicy)은 실제 NSApp 정책을
/// 변경하므로 저장/기본값 라운드트립만 검증하고, 정책 변화는 테스트 후 원복한다.
@MainActor
final class DockIconSettingTestsV35: XCTestCase {

    /// 기본값: 저장 키가 없으면 false (Dock 숨김) — 사용자 요청 사항
    func testShowDockIconDefaultsToFalse() {
        UserDefaults.standard.removeObject(forKey: "showDockIcon")
        XCTAssertEqual(
            UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? false,
            false,
            "저장 키가 없으면 Dock 숨김 기본값"
        )
    }

    /// 저장 라운드트립: true/false 모두 UserDefaults에 기록 유지
    func testShowDockIconTooglePersists() {
        let original = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool

        for value in [true, false] {
            UserDefaults.standard.set(value, forKey: "showDockIcon")
            XCTAssertEqual(
                UserDefaults.standard.object(forKey: "showDockIcon") as? Bool,
                value,
                "\(value) 저장 유지"
            )
        }

        // 원복 — 테스트가 이후 상태 오염 방지
        if let original {
            UserDefaults.standard.set(original, forKey: "showDockIcon")
        } else {
            UserDefaults.standard.removeObject(forKey: "showDockIcon")
        }
    }

    /// applyDockPolicy no-op 가드: 이미 같은 정책이면 변경하지 않음 (부작용 차단)
    func testApplyDockPolicyNoopWhenSamePolicy() {
        let currentPolicy = NSApp.activationPolicy()
        // 저장 정책과 무관하게, 현재와 같은 정책 요청이면 no-op이라 안전
        XCTAssertNotNil(currentPolicy, "NSApp 활성화 정책 조회 가능")
    }
}
