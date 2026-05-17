import CoreGraphics
import CoreText
import PDFKit
import XCTest
@testable import AppleVisionOCRCore

final class PDFTextOverlayWriterTests: XCTestCase {
    func testPreservesSourcePageMediaBox() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.pdf")
        let outputURL = directory.appendingPathComponent("output.pdf")
        let mediaBox = CGRect(x: 0, y: 0, width: 595.92, height: 842.88)
        try makeSourcePDF(at: sourceURL, mediaBox: mediaBox)

        let sourceDocument = try XCTUnwrap(CGPDFDocument(sourceURL as CFURL))
        let writer = PDFTextOverlayWriter()
        try writer.write(
            sourceDocument: sourceDocument,
            pages: [
                PDFPageOCRResult(
                    pageNumber: 1,
                    geometry: PDFPageGeometry(mediaBox: mediaBox, rotation: 0),
                    overlays: []
                )
            ],
            to: outputURL
        )

        let outputPage = try XCTUnwrap(CGPDFDocument(outputURL as CFURL)?.page(at: 1))
        let outputMediaBox = outputPage.getBoxRect(.mediaBox)
        XCTAssertEqual(outputMediaBox.width, mediaBox.width, accuracy: 0.001)
        XCTAssertEqual(outputMediaBox.height, mediaBox.height, accuracy: 0.001)
    }

    func testPreservesRotatedSourcePageMediaBoxWithoutSwappingDimensions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.pdf")
        let outputURL = directory.appendingPathComponent("output.pdf")
        let mediaBox = CGRect(x: 0, y: 0, width: 841.89, height: 595.276)
        try makeSourcePDF(at: sourceURL, mediaBox: mediaBox)

        let sourceDocument = try XCTUnwrap(CGPDFDocument(sourceURL as CFURL))
        let writer = PDFTextOverlayWriter()
        try writer.write(
            sourceDocument: sourceDocument,
            pages: [
                PDFPageOCRResult(
                    pageNumber: 1,
                    geometry: PDFPageGeometry(mediaBox: mediaBox, rotation: 270),
                    overlays: []
                )
            ],
            to: outputURL
        )

        let outputPage = try XCTUnwrap(CGPDFDocument(outputURL as CFURL)?.page(at: 1))
        let outputMediaBox = outputPage.getBoxRect(.mediaBox)
        XCTAssertEqual(outputMediaBox.width, mediaBox.width, accuracy: 0.001)
        XCTAssertEqual(outputMediaBox.height, mediaBox.height, accuracy: 0.001)
    }

    func testOverlayTextCanScaleWiderToMatchRecognizedBoundingBoxEnd() {
        let scale = PDFTextOverlayWriter.horizontalScale(lineWidth: 50, rectWidth: 125)

        XCTAssertEqual(scale, 2.5, accuracy: 0.001)
    }

    func testOverlayTextCanScaleNarrowerToMatchRecognizedBoundingBoxEnd() {
        let scale = PDFTextOverlayWriter.horizontalScale(lineWidth: 200, rectWidth: 125)

        XCTAssertEqual(scale, 0.625, accuracy: 0.001)
    }

    func testRasterizedBackgroundRemovesSourceSelectableText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.pdf")
        let outputURL = directory.appendingPathComponent("output.pdf")
        let mediaBox = CGRect(x: 0, y: 0, width: 240, height: 120)
        try makeSourcePDF(at: sourceURL, mediaBox: mediaBox, text: "SOURCE TEXT")

        let sourceDocument = try XCTUnwrap(CGPDFDocument(sourceURL as CFURL))
        let writer = PDFTextOverlayWriter()
        try writer.write(
            sourceDocument: sourceDocument,
            pages: [
                PDFPageOCRResult(
                    pageNumber: 1,
                    geometry: PDFPageGeometry(mediaBox: mediaBox, rotation: 0),
                    overlays: [],
                    backgroundImage: makeBackgroundImage()
                )
            ],
            to: outputURL
        )

        let outputDocument = try XCTUnwrap(PDFDocument(url: outputURL))
        XCTAssertFalse((outputDocument.page(at: 0)?.string ?? "").contains("SOURCE TEXT"))
    }

    private func makeSourcePDF(at url: URL, mediaBox: CGRect, text: String? = nil) throws {
        var box = mediaBox
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            XCTFail("failed to create source PDF")
            return
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 72, y: 72, width: 96, height: 48))
        if let text {
            drawText(text, at: CGPoint(x: 24, y: 32), into: context)
        }
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

    private func makeBackgroundImage() throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 24,
            height: 12,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("failed to create bitmap context")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 12))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 2, y: 2, width: 8, height: 4))
        return try XCTUnwrap(context.makeImage())
    }
}
