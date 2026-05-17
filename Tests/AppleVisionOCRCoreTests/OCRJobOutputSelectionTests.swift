import XCTest
@testable import AppleVisionOCRCore

final class OCRJobOutputSelectionTests: XCTestCase {
    func testAllowsTextOnlyWithoutPageBreaks() throws {
        let selection = try OCRJobOutputSelection(
            writesText: true,
            writesPDF: false,
            includesPageBreaks: false
        )

        XCTAssertEqual(selection.outputMode, .plainText)
    }

    func testAllowsSearchablePDFOnly() throws {
        let selection = try OCRJobOutputSelection(
            writesText: false,
            writesPDF: true,
            includesPageBreaks: false
        )

        XCTAssertEqual(selection.outputMode, .searchablePDF)
    }

    func testAllowsTextAndSearchablePDFWithoutPageBreaks() throws {
        let selection = try OCRJobOutputSelection(
            writesText: true,
            writesPDF: true,
            includesPageBreaks: false
        )

        XCTAssertEqual(selection.outputMode, .textAndSearchablePDF)
    }

    func testPageBreaksAreTextSuboption() throws {
        let selection = try OCRJobOutputSelection(
            writesText: true,
            writesPDF: true,
            includesPageBreaks: true
        )

        XCTAssertTrue(selection.outputMode.writesText)
        XCTAssertTrue(selection.outputMode.writesPDF)
        XCTAssertTrue(selection.outputMode.includesPageBreaks)
    }

    func testRejectsPageBreaksWithoutText() {
        XCTAssertThrowsError(try OCRJobOutputSelection(
            writesText: false,
            writesPDF: true,
            includesPageBreaks: true
        )) { error in
            XCTAssertEqual(error as? OCRJobOptionError, .pageBreaksRequireText)
        }
    }
}
