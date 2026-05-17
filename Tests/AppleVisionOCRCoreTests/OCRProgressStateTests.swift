import XCTest
@testable import AppleVisionOCRCore

final class OCRProgressStateTests: XCTestCase {
    func testPercentUsesCompletedPagesOverTotalPages() {
        let event = OCRProgressEvent(
            stage: .recognizingText,
            currentFile: "sample.pdf",
            completedPages: 2,
            totalPages: 5,
            message: "OCR page 2/5"
        )

        XCTAssertEqual(event.percent, 40)
    }

    func testZeroTotalPagesReportsZeroPercent() {
        let event = OCRProgressEvent(
            stage: .starting,
            currentFile: nil,
            completedPages: 0,
            totalPages: 0,
            message: "Starting"
        )

        XCTAssertEqual(event.percent, 0)
    }
}
