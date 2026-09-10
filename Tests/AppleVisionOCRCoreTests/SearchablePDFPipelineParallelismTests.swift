import CoreGraphics
import XCTest
@testable import AppleVisionOCRCore

final class SearchablePDFPipelineParallelismTests: XCTestCase {
    func testProcessesPagesConcurrentlyWithinSinglePDF() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let inputURL = temporaryDirectory.appendingPathComponent("input.pdf")
        let textOutputURL = temporaryDirectory.appendingPathComponent("input.txt")
        try makeBlankPDF(at: inputURL, pageCount: 6)

        let recognizer = TrackingTextRecognizer(delay: 0.05)
        let pipeline = SearchablePDFPipeline(
            renderer: StubPDFRenderer(),
            recognizer: recognizer,
            writer: PDFTextOverlayWriter(),
            textWriter: TextOutputWriter(),
            textPresenceDetector: PDFTextPresenceDetector()
        )

        let options = try OCRJobOptions(
            inputURL: inputURL,
            pdfOutputURL: nil,
            textOutputURL: textOutputURL,
            outputMode: .plainText,
            pageParallelism: try OCRJobParallelism(count: 3)
        )

        try pipeline.run(job: options)

        XCTAssertGreaterThanOrEqual(recognizer.maxConcurrentCalls, 2)
        XCTAssertLessThanOrEqual(recognizer.maxConcurrentCalls, 3)
    }

    func testPassesConfiguredRenderScaleToRenderer() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let inputURL = temporaryDirectory.appendingPathComponent("input.pdf")
        let textOutputURL = temporaryDirectory.appendingPathComponent("input.txt")
        try makeBlankPDF(at: inputURL, pageCount: 2)

        let renderer = TrackingPDFRenderer()
        let pipeline = SearchablePDFPipeline(
            renderer: renderer,
            recognizer: TrackingTextRecognizer(delay: 0),
            writer: PDFTextOverlayWriter(),
            textWriter: TextOutputWriter(),
            textPresenceDetector: PDFTextPresenceDetector()
        )

        let options = try OCRJobOptions(
            inputURL: inputURL,
            pdfOutputURL: nil,
            textOutputURL: textOutputURL,
            outputMode: .plainText,
            pageParallelism: try OCRJobParallelism(count: 2),
            renderScale: .balanced
        )

        try pipeline.run(job: options)

        XCTAssertEqual(renderer.scales, [.balanced, .balanced])
    }

    private func makeBlankPDF(at url: URL, pageCount: Int) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            XCTFail("failed to create PDF context")
            return
        }

        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            context.endPDFPage()
        }

        context.closePDF()
    }
}

private final class StubPDFRenderer: PDFRendering {
    func render(page: CGPDFPage, scale: OCRRenderScale) throws -> RenderedPDFPage {
        let mediaBox = page.getBoxRect(.mediaBox)
        let geometry = PDFPageGeometry(mediaBox: mediaBox, rotation: Int(page.rotationAngle))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw AppleVisionOCRError.pdfFailure("failed to create stub image")
        }

        return RenderedPDFPage(image: image, geometry: geometry)
    }
}

private final class TrackingPDFRenderer: PDFRendering {
    private let lock = NSLock()
    private(set) var scales: [OCRRenderScale] = []

    func render(page: CGPDFPage, scale: OCRRenderScale) throws -> RenderedPDFPage {
        lock.lock()
        scales.append(scale)
        lock.unlock()

        let mediaBox = page.getBoxRect(.mediaBox)
        let geometry = PDFPageGeometry(mediaBox: mediaBox, rotation: Int(page.rotationAngle))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw AppleVisionOCRError.pdfFailure("failed to create tracking image")
        }

        return RenderedPDFPage(image: image, geometry: geometry)
    }
}

private final class TrackingTextRecognizer: TextRecognizing {
    private let delay: TimeInterval
    private let lock = NSLock()
    private var activeCalls = 0
    private(set) var maxConcurrentCalls = 0

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func recognize(
        image: CGImage,
        languages: [String],
        recognitionLevel: OCRRecognitionLevel,
        usesLanguageCorrection: Bool
    ) throws -> [RecognizedTextBox] {
        lock.lock()
        activeCalls += 1
        maxConcurrentCalls = max(maxConcurrentCalls, activeCalls)
        lock.unlock()

        Thread.sleep(forTimeInterval: delay)

        lock.lock()
        activeCalls -= 1
        lock.unlock()

        return []
    }
}
