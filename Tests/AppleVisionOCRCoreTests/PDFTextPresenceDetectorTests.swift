import CoreGraphics
import CoreText
import XCTest
@testable import AppleVisionOCRCore

final class PDFTextPresenceDetectorTests: XCTestCase {
    func testDetectsPagesWithExtractableText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("text.pdf")
        try makeTextPDF(at: url, text: "Existing selectable text")

        let report = try PDFTextPresenceDetector().inspect(url)

        XCTAssertTrue(report.hasText)
        XCTAssertEqual(report.textPageNumbers, [1])
    }

    func testIgnoresImageOnlyPages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("image.pdf")
        try makeImageOnlyPDF(at: url)

        let report = try PDFTextPresenceDetector().inspect(url)

        XCTAssertFalse(report.hasText)
        XCTAssertEqual(report.textPageNumbers, [])
    }

    func testInspectsOnlySelectedPages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("selected-pages.pdf")
        try makeTextPDF(at: url, pageTexts: ["Outside selection", nil, "Inside selection"])

        let report = try PDFTextPresenceDetector().inspect(url, pageNumbers: [2, 3])

        XCTAssertTrue(report.hasText)
        XCTAssertEqual(report.textPageNumbers, [3])
    }

    private func makeTextPDF(at url: URL, text: String) throws {
        try makeTextPDF(at: url, pageTexts: [text])
    }

    private func makeTextPDF(at url: URL, pageTexts: [String?]) throws {
        var box = CGRect(x: 0, y: 0, width: 240, height: 120)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            XCTFail("failed to create PDF")
            return
        }
        for text in pageTexts {
            context.beginPDFPage(nil)
            if let text {
                drawText(text, at: CGPoint(x: 24, y: 64), into: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func makeImageOnlyPDF(at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 240, height: 120)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            XCTFail("failed to create PDF")
            return
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 24, y: 24, width: 72, height: 36))
        context.endPDFPage()
        context.closePDF()
    }

    private func drawText(_ text: String, at point: CGPoint, into context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)
        ] as CFDictionary
        guard let attributedText = CFAttributedStringCreate(nil, text as CFString, attributes) else {
            return
        }

        let line = CTLineCreateWithAttributedString(attributedText)
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
