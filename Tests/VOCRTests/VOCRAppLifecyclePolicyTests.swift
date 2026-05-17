import XCTest
import AppKit
@testable import VOCR

final class VOCRAppLifecyclePolicyTests: XCTestCase {
    func testTerminalJobStatesScheduleAppTermination() {
        XCTAssertTrue(VOCRAppLifecyclePolicy.shouldTerminateAfterFinish(.completed))
        XCTAssertTrue(VOCRAppLifecyclePolicy.shouldTerminateAfterFinish(.canceled))
        XCTAssertTrue(VOCRAppLifecyclePolicy.shouldTerminateAfterFinish(.failed))
    }

    func testNonTerminalJobStatesDoNotScheduleAppTermination() {
        XCTAssertFalse(VOCRAppLifecyclePolicy.shouldTerminateAfterFinish(.idle))
        XCTAssertFalse(VOCRAppLifecyclePolicy.shouldTerminateAfterFinish(.running))
        XCTAssertFalse(VOCRAppLifecyclePolicy.shouldTerminateAfterFinish(.paused))
    }

    @MainActor
    func testOptionWindowContainsQuitButton() {
        _ = NSApplication.shared
        let controller = VOCRWindowController(files: [])

        let hasQuitButton = controller.window?.contentView
            .flatMap { Self.containsButton(titled: "종료", in: $0) } ?? false

        XCTAssertTrue(hasQuitButton)
    }

    @MainActor
    func testOptionWindowWarnsThatSpeedModeIsEnglishOnly() {
        _ = NSApplication.shared
        let controller = VOCRWindowController(files: [])

        let hasSpeedMode = controller.window?.contentView
            .flatMap { Self.containsText("속도 우선 (영문 전용)", in: $0) } ?? false

        XCTAssertTrue(hasSpeedMode)
    }

    @MainActor
    func testOptionWindowContainsKoreanSafeSpeedPreset() {
        _ = NSApplication.shared
        let controller = VOCRWindowController(files: [])

        let hasKoreanSafeSpeedPreset = controller.window?.contentView
            .flatMap { Self.containsText("한국어 속도 균형", in: $0) } ?? false

        XCTAssertTrue(hasKoreanSafeSpeedPreset)
    }

    @MainActor
    private static func containsButton(titled title: String, in view: NSView) -> Bool {
        if let button = view as? NSButton, button.title == title {
            return true
        }

        return view.subviews.contains { containsButton(titled: title, in: $0) }
    }

    @MainActor
    private static func containsText(_ text: String, in view: NSView) -> Bool {
        if let control = view as? NSControl, control.stringValue.contains(text) {
            return true
        }
        if let popup = view as? NSPopUpButton {
            return popup.itemTitles.contains { $0.contains(text) }
        }

        return view.subviews.contains { containsText(text, in: $0) }
    }
}
