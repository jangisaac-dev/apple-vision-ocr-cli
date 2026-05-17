import XCTest
@testable import AppleVisionOCRCore

final class OutputPathTests: XCTestCase {
    func testDerivesDefaultOutputNextToInput() throws {
        let input = URL(fileURLWithPath: "/tmp/input.pdf")

        let output = try OutputPathResolver.defaultOutputURL(for: input)

        XCTAssertEqual(output.path, "/tmp/input_ocr.pdf")
    }

    func testDerivesDefaultOutputForNamesWithMultipleDots() throws {
        let input = URL(fileURLWithPath: "/tmp/file.name.pdf")

        let output = try OutputPathResolver.defaultOutputURL(for: input)

        XCTAssertEqual(output.path, "/tmp/file.name_ocr.pdf")
    }

    func testDerivesDefaultTextOutputNextToInput() throws {
        let input = URL(fileURLWithPath: "/tmp/file.name.pdf")

        let output = try OutputPathResolver.defaultTextOutputURL(for: input)

        XCTAssertEqual(output.path, "/tmp/file.name.txt")
    }

    func testRejectsNonPDFInputForDefaultOutput() {
        let input = URL(fileURLWithPath: "/tmp/input.png")

        XCTAssertThrowsError(try OutputPathResolver.defaultOutputURL(for: input)) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .inputFileProblem)
        }
    }
}
