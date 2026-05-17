import XCTest
@testable import AppleVisionOCRCore

final class VisionLanguageResolverTests: XCTestCase {
    func testResolvesDefaultShortLanguageAliasesForVision() {
        XCTAssertEqual(
            VisionLanguageResolver.resolve(["ko", "en"]),
            ["ko-KR", "en-US"]
        )
    }

    func testLeavesConcreteLanguageIdentifiersUntouched() {
        XCTAssertEqual(
            VisionLanguageResolver.resolve(["ja-JP", "en-US"]),
            ["ja-JP", "en-US"]
        )
    }

    func testFastRecognitionDoesNotSupportKorean() throws {
        XCTAssertEqual(
            try VisionLanguageResolver.unsupportedLanguages(["ko", "en"], recognitionLevel: .fast),
            ["ko-KR"]
        )
    }

    func testFastRecognitionSupportsEnglish() throws {
        XCTAssertEqual(
            try VisionLanguageResolver.unsupportedLanguages(["en"], recognitionLevel: .fast),
            []
        )
    }
}
