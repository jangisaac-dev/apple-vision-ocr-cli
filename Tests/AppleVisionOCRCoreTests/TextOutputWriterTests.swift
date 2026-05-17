import CoreGraphics
import XCTest
@testable import AppleVisionOCRCore

final class TextOutputWriterTests: XCTestCase {
    func testRendersRecognizedTextByPage() {
        let writer = TextOutputWriter()
        let text = writer.render(
            pages: [
                page(1, texts: ["Hello", "World"]),
                page(2, texts: ["Second page"])
            ],
            includePageBreaks: false
        )

        XCTAssertEqual(text, "Hello\nWorld\n\nSecond page\n")
    }

    func testRendersPageBreaksWhenRequested() {
        let writer = TextOutputWriter()
        let text = writer.render(
            pages: [
                page(1, texts: ["Hello"]),
                page(2, texts: ["Second page"])
            ],
            includePageBreaks: true
        )

        XCTAssertEqual(text, "===== Page 1 =====\n\nHello\n\n===== Page 2 =====\n\nSecond page\n")
    }

    private func page(_ pageNumber: Int, texts: [String]) -> PDFPageOCRResult {
        PDFPageOCRResult(
            pageNumber: pageNumber,
            geometry: PDFPageGeometry(mediaBox: CGRect(x: 0, y: 0, width: 100, height: 100), rotation: 0),
            overlays: texts.map { PDFTextOverlay(text: $0, rect: .zero) }
        )
    }
}
