import XCTest
@testable import AIModelTalk

/// v2.0 T-83 — 온보딩 슬라이드 메타 테스트 (v2.1 T-101 리디자인 구조 반영)
final class OnboardingTestsV20: XCTestCase {

    func testThreeSlidesWithContent() {
        XCTAssertEqual(OnboardingView.slides.count, 3)
        for slide in OnboardingView.slides {
            XCTAssertFalse(slide.title.isEmpty, "슬라이드 제목 존재")
            XCTAssertFalse(slide.subtitle.isEmpty, "부제 존재")
            XCTAssertEqual(slide.features.count, 3, "피처 3행 구성")
            for feature in slide.features {
                XCTAssertFalse(feature.title.isEmpty, "피처 제목 존재")
                XCTAssertGreaterThan(feature.detail.count, 4, "피처 상세 문구 존재")
            }
        }
    }

    func testSlidesMentionKeyFeatures() {
        let all = OnboardingView.slides.map { slide in
            slide.title + " " + slide.subtitle + " "
                + slide.features.map { $0.title + " " + $0.detail }.joined(separator: " ")
        }.joined(separator: " ")
        XCTAssertTrue(all.contains("공급자"), "공급자 설정 안내 포함")
        XCTAssertTrue(all.contains("⌥ Space"), "런처 단축키 안내 포함")
        XCTAssertTrue(all.contains("⌘ F"), "전역 검색 안내 포함")
    }

    func testWelcomeSlideUsesBrandName() {
        // 파일명이 아닌 브랜드명 표기 (v2.1 T-101 사용자 피드백)
        XCTAssertEqual(OnboardingView.slides[0].title, "AI Model Talk")
        XCTAssertTrue(OnboardingView.slides[0].subtitle.contains("AI 모델 톡"), "한글 병기 포함")
    }
}
