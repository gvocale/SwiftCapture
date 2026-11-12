import XCTest
import AVFoundation
import CoreGraphics
@testable import SwiftCapture

final class WindowTargetTests: XCTestCase {
    func testEvenPixelSizeFloorsOddAndKeepsEven() {
        XCTAssertEqual(WindowTargetRules.evenPixelSize(CGSize(width: 1281, height: 801)), CGSize(width: 1280, height: 800))
        XCTAssertEqual(WindowTargetRules.evenPixelSize(CGSize(width: 1280, height: 800)), CGSize(width: 1280, height: 800))
        XCTAssertEqual(WindowTargetRules.evenPixelSize(CGSize(width: 0, height: 1)), CGSize(width: 2, height: 2))
    }

    func testPixelSizeAppliesScale() {
        XCTAssertEqual(WindowTargetRules.pixelSize(points: CGSize(width: 640, height: 400), scale: 2), CGSize(width: 1280, height: 800))
        XCTAssertEqual(WindowTargetRules.pixelSize(points: CGSize(width: 390, height: 844), scale: 2), CGSize(width: 780, height: 1688))
    }

    func testBundleMismatch() {
        XCTAssertNil(WindowTargetRules.bundleMismatch(expected: nil, actual: "x", windowID: 5))
        XCTAssertNil(WindowTargetRules.bundleMismatch(expected: "com.google.Chrome", actual: "com.google.Chrome", windowID: 5))
        XCTAssertNotNil(WindowTargetRules.bundleMismatch(expected: "com.google.Chrome", actual: "com.apple.Safari", windowID: 5))
        XCTAssertNotNil(WindowTargetRules.bundleMismatch(expected: "com.google.Chrome", actual: nil, windowID: 5))
    }

    func testOptionRules() {
        func v(_ id: Int? = nil, _ b: String? = nil, _ a: String? = nil, app: String? = nil, area: Bool = false, screen: Int = 1) -> String? {
            WindowTargetRules.validateOptions(windowID: id, expectBundleID: b, activation: a, app: app, areaGiven: area, screen: screen)
        }
        XCTAssertNil(v())
        XCTAssertNil(v(42, "com.google.Chrome", "preserve"))
        XCTAssertNotNil(v(0))
        XCTAssertNotNil(v(nil, "com.google.Chrome"))
        XCTAssertNotNil(v(42, nil, "bogus"))
        XCTAssertNotNil(v(42, nil, "raise"))
        XCTAssertNotNil(v(42, app: "Safari"))
        XCTAssertNotNil(v(42, area: true))
        XCTAssertNotNil(v(42, screen: 2))
        XCTAssertNil(v(nil, nil, "raise", app: "Safari"))
    }

    func testRec709Tags() {
        let props = VideoSettings.rec709ColorProperties
        XCTAssertEqual(props.count, 3)
        let s = VideoSettings.default(resolution: CGSize(width: 640, height: 480)).avSettings
        XCTAssertNotNil(s[AVVideoColorPropertiesKey])
    }

    func testHighQualityLargeStaysH264() {
        let v = VideoSettings.optimized(fps: 30, quality: .high, resolution: CGSize(width: 3840, height: 2160), for: .mov)
        XCTAssertEqual(v.codec, .h264)
    }
}
