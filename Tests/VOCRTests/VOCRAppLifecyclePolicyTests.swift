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
        for language in [VOCRLanguage.english, .korean] {
            Self.withLanguage(language) {
                _ = NSApplication.shared
                let controller = VOCRWindowController(files: [])

                let hasQuitButton = controller.window?.contentView
                    .flatMap { Self.containsButton(titled: VOCRStrings.buttonQuit.text, in: $0) } ?? false

                XCTAssertTrue(hasQuitButton)
            }
        }
    }

    @MainActor
    func testOptionWindowWarnsThatSpeedModeIsEnglishOnly() {
        for language in [VOCRLanguage.english, .korean] {
            Self.withLanguage(language) {
                _ = NSApplication.shared
                let controller = VOCRWindowController(files: [])

                let hasSpeedMode = controller.window?.contentView
                    .flatMap { Self.containsText(VOCRStrings.popupRecognitionSpeedFirst.text, in: $0) } ?? false

                XCTAssertTrue(hasSpeedMode)
            }
        }
    }

    @MainActor
    func testOptionWindowContainsKoreanSafeSpeedPreset() {
        for language in [VOCRLanguage.english, .korean] {
            Self.withLanguage(language) {
                _ = NSApplication.shared
                let controller = VOCRWindowController(files: [])

                let hasKoreanSafeSpeedPreset = controller.window?.contentView
                    .flatMap { Self.containsText(VOCRStrings.popupRenderScaleBalanced.text, in: $0) } ?? false

                XCTAssertTrue(hasKoreanSafeSpeedPreset)
            }
        }
    }

    @MainActor
    func testOptionWindowContainsDisableLanguageCorrectionCheckbox() {
        for language in [VOCRLanguage.english, .korean] {
            Self.withLanguage(language) {
                _ = NSApplication.shared
                let controller = VOCRWindowController(files: [])

                let hasCheckbox = controller.window?.contentView
                    .flatMap { Self.containsButton(titled: VOCRStrings.checkboxDisableLanguageCorrection.text, in: $0) } ?? false

                XCTAssertTrue(hasCheckbox)
            }
        }
    }

    @MainActor
    func testOptionWindowLabelsParallelismAsWorkerProcesses() {
        for language in [VOCRLanguage.english, .korean] {
            Self.withLanguage(language) {
                _ = NSApplication.shared
                let controller = VOCRWindowController(files: [])

                let hasWorkerProcessLabel = controller.window?.contentView
                    .flatMap { Self.containsText(VOCRStrings.headerWorkerProcessCount.text, in: $0) } ?? false

                XCTAssertTrue(hasWorkerProcessLabel)
            }
        }
    }

    func testEveryStringHasEnglishAndKoreanTextWithoutHangulInEnglish() {
        for (key, entry) in VOCRStrings.all {
            XCTAssertFalse(entry.english.isEmpty, "Empty English text for \(key)")
            XCTAssertFalse(entry.korean.isEmpty, "Empty Korean text for \(key)")
            XCTAssertFalse(
                entry.english.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 },
                "English text contains Hangul for \(key)"
            )
        }
    }

    @MainActor
    func testInterpolatedStringsRenderTypedValuesInBothLanguages() {
        let workerCount = 7
        let fileName = "sample-input.pdf"
        let generatedFiles = "sample-input_ocr.pdf, sample-input.txt"
        let recognitionLevel = "accurate"
        let renderScale = 1.5
        let parallelism = workerCount
        let minimumCount = 1
        let maximumCount = 16
        let errorDescription = "sample inspection failure"
        let detail = "sample-input.pdf already contains text"
        let omittedCount = 3

        for language in [VOCRLanguage.english, .korean] {
            Self.withLanguage(language) {
                let entries: [(String, String, [String])] = [
                    ("logWorkerCountChanged", VOCRStrings.logWorkerCountChanged(workerCount), [String(workerCount)]),
                    ("messageWorkerCount", VOCRStrings.messageWorkerCount(workerCount), [String(workerCount)]),
                    ("logFileStarted", VOCRStrings.logFileStarted(fileName), [fileName]),
                    ("messageFileCompleted", VOCRStrings.messageFileCompleted(fileName), [fileName]),
                    ("logPlannedOutput", VOCRStrings.logPlannedOutput(fileName), [fileName]),
                    ("previewGeneratedFiles", VOCRStrings.previewGeneratedFiles(generatedFiles), [generatedFiles]),
                    (
                        "logJobStartedWithOptions",
                        VOCRStrings.logJobStartedWithOptions(
                            recognitionLevel: recognitionLevel,
                            renderScale: renderScale,
                            workerCount: parallelism
                        ),
                        [recognitionLevel, String(renderScale), String(parallelism)]
                    ),
                    (
                        "logInvalidParallelism",
                        VOCRStrings.logInvalidParallelism(
                            minimumCount: minimumCount,
                            maximumCount: maximumCount
                        ),
                        [String(minimumCount), String(maximumCount)]
                    ),
                    (
                        "logExistingTextInspectionFailed",
                        VOCRStrings.logExistingTextInspectionFailed(
                            fileName: fileName,
                            errorDescription: errorDescription
                        ),
                        [fileName, errorDescription]
                    ),
                    (
                        "alertExistingTextBody",
                        VOCRStrings.alertExistingTextBody(detail: detail, omittedCount: omittedCount),
                        [detail, String(omittedCount)]
                    ),
                    ("alertMoreFiles", VOCRStrings.alertMoreFiles(omittedCount), [String(omittedCount)])
                ]

                for (key, rendered, samples) in entries {
                    for sample in samples {
                        XCTAssertTrue(rendered.contains(sample), "Missing \(sample) in \(key) for \(language)")
                    }
                    XCTAssertFalse(rendered.contains(#"\("#), "Unrendered interpolation in \(key) for \(language)")
                    if language == .english {
                        XCTAssertFalse(
                            rendered.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 },
                            "English text contains Hangul for \(key)"
                        )
                    }
                }
            }
        }
    }

    func testLanguageResolverUsesOverrideAndKoreanPreferredLanguage() {
        XCTAssertEqual(
            VOCRLanguage.resolve(environmentValue: "en", preferredLanguages: ["ko-KR"]),
            .english
        )
        XCTAssertEqual(
            VOCRLanguage.resolve(environmentValue: "ko", preferredLanguages: ["en-US"]),
            .korean
        )
        XCTAssertEqual(
            VOCRLanguage.resolve(environmentValue: "other", preferredLanguages: ["ko-KR"]),
            .korean
        )
        XCTAssertEqual(
            VOCRLanguage.resolve(environmentValue: nil, preferredLanguages: ["en-US"]),
            .english
        )
    }

    @MainActor
    func testFileListScrollsHorizontallyInsteadOfWrappingLongPaths() throws {
        _ = NSApplication.shared
        let longPath = "/tmp/" + String(repeating: "very-long-directory-name/", count: 12) + "input.pdf"
        let files = (1...30).map { URL(fileURLWithPath: longPath + "-\($0)") }
        let controller = VOCRWindowController(files: files)
        let contentView = try XCTUnwrap(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(Self.scrollView(containingText: "input.pdf-30", in: contentView))
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        textView.layoutManager?.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        textView.sizeToFit()

        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertGreaterThan(textView.frame.width, scrollView.contentSize.width)
        XCTAssertGreaterThan(textView.frame.height, scrollView.contentSize.height)
        XCTAssertLessThanOrEqual(scrollView.frame.height, 80)
    }

    @MainActor
    private static func scrollView(containingText text: String, in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView,
           let textView = scrollView.documentView as? NSTextView,
           textView.string.contains(text) {
            return scrollView
        }

        return view.subviews.lazy.compactMap { scrollView(containingText: text, in: $0) }.first
    }

    @MainActor
    private static func withLanguage(_ language: VOCRLanguage, body: () -> Void) {
        let previousLanguage = VOCRStrings.language
        VOCRStrings.language = language
        defer { VOCRStrings.language = previousLanguage }
        body()
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
