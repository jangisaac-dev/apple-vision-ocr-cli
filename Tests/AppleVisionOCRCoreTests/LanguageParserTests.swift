import XCTest
@testable import AppleVisionOCRCore

final class LanguageParserTests: XCTestCase {
    func testParsesCommaSeparatedLanguages() throws {
        XCTAssertEqual(try LanguageParser.parse("ko,en"), ["ko", "en"])
    }

    func testTrimsWhitespaceAroundLanguages() throws {
        XCTAssertEqual(try LanguageParser.parse("ko, en"), ["ko", "en"])
    }

    func testRejectsEmptyLanguageList() {
        XCTAssertThrowsError(try LanguageParser.parse(" , ")) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }
}
