import XCTest
@testable import AppleVisionOCRCore

final class OutputModeTests: XCTestCase {
    func testRequiresAtLeastOneOutput() {
        XCTAssertThrowsError(try OCRJobOutputMode(writesPDF: false, writesText: false, includesPageBreaks: false)) { error in
            XCTAssertEqual(error as? OCRJobOptionError, .missingOutput)
        }
    }

    func testPageBreaksRequireTextOutput() {
        XCTAssertThrowsError(try OCRJobOutputMode(writesPDF: true, writesText: false, includesPageBreaks: true)) { error in
            XCTAssertEqual(error as? OCRJobOptionError, .pageBreaksRequireText)
        }
    }

    func testAllowsPageDividedTextOnly() throws {
        let mode = try OCRJobOutputMode(writesPDF: false, writesText: true, includesPageBreaks: true)

        XCTAssertFalse(mode.writesPDF)
        XCTAssertTrue(mode.writesText)
        XCTAssertTrue(mode.includesPageBreaks)
    }

    func testJobOptionsRequirePDFURLForPDFMode() {
        XCTAssertThrowsError(try OCRJobOptions(
            inputURL: URL(fileURLWithPath: "/tmp/input.pdf"),
            pdfOutputURL: nil,
            textOutputURL: nil,
            outputMode: .searchablePDF
        )) { error in
            XCTAssertEqual(error as? OCRJobOptionError, .missingPDFOutputURL)
        }
    }

    func testJobOptionsRejectFastRecognitionWithUnsupportedLanguages() {
        XCTAssertThrowsError(try OCRJobOptions(
            inputURL: URL(fileURLWithPath: "/tmp/input.pdf"),
            pdfOutputURL: nil,
            textOutputURL: URL(fileURLWithPath: "/tmp/input.txt"),
            outputMode: .plainText,
            languages: ["ko", "en"],
            recognitionLevel: .fast
        )) { error in
            XCTAssertEqual(error as? OCRJobOptionError, .unsupportedRecognitionLanguage)
        }
    }

    func testJobOptionsDefaultToSharedParallelismDefault() throws {
        let options = try OCRJobOptions(
            inputURL: URL(fileURLWithPath: "/tmp/input.pdf"),
            pdfOutputURL: nil,
            textOutputURL: URL(fileURLWithPath: "/tmp/input.txt"),
            outputMode: .plainText
        )

        XCTAssertEqual(options.pageParallelism, .default)
    }
}
