import CoreGraphics
import XCTest
@testable import AppleVisionOCRCore

final class SearchablePDFPipelineMarkdownTests: XCTestCase {
    func testMarkdownAndPageJSONUseOrderedAnalysis() throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        for json in [false, true] {
            let output = directory.appendingPathComponent(json ? "pages.json" : "document.md")
            let pipeline = SearchablePDFPipeline(recognizer: MarkdownTextRecognizer(),
                                                layoutLoader: { MarkdownLayoutStub() }, tableRecognizer: MarkdownTableStub())
            let options = try OCRJobOptions(inputURL: directory.appendingPathComponent("input.pdf"),
                                            pdfOutputURL: nil, textOutputURL: nil, outputMode: .markdown,
                                            markdownOutputURL: json ? nil : output,
                                            markdownPagesOutputURL: json ? output : nil)
            try pipeline.run(job: options)
            if json {
                let pages = try JSONDecoder().decode([MarkdownPage].self, from: Data(contentsOf: output))
                XCTAssertEqual(pages.map(\.pdfPage), [1, 2])
                XCTAssertEqual(pages[0].blocks.map(\.text), ["한글 제목", "| 표 |\n| --- |\n| 내용 |"])
            } else {
                XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "[PDF p. 1]\n\n# 한글 제목\n\n| 표 |\n| --- |\n| 내용 |\n\n[PDF p. 2]\n\n# 한글 제목\n\n| 표 |\n| --- |\n| 내용 |\n")
            }
            XCTAssertThrowsError(try pipeline.run(job: options)) {
                XCTAssertEqual($0 as? AppleVisionOCRError, .outputAlreadyExists("output already exists: \(output.path)"))
            }
        }
    }

    func testMissingLayoutStopsBeforeRenderingOrOCR() throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipeline = SearchablePDFPipeline(renderer: NeverRender(), recognizer: NeverRecognize(),
                                            layoutLoader: { throw AppleVisionOCRError.visionFailure(LayoutModel.missingMessage) })
        let options = try OCRJobOptions(inputURL: directory.appendingPathComponent("input.pdf"),
                                        pdfOutputURL: nil, textOutputURL: nil, outputMode: .markdown,
                                        markdownOutputURL: directory.appendingPathComponent("output.md"))
        XCTAssertThrowsError(try pipeline.run(job: options)) {
            XCTAssertEqual($0 as? AppleVisionOCRError, .visionFailure(LayoutModel.missingMessage))
        }
    }

    func testCropRoundsOutwardsAndClampsToPage() throws {
        let context = CGContext(data: nil, width: 10, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let crop = SearchablePDFPipeline.crop(context.makeImage()!, rect: CGRect(x: -0.05, y: 0.12, width: 0.32, height: 0.25))!
        XCTAssertEqual(crop.image.width, 3)
        XCTAssertEqual(crop.image.height, 6)
        XCTAssertEqual(crop.rect, CGRect(x: 0, y: 0.1, width: 0.3, height: 0.3))
        let lines = SearchablePDFPipeline.layoutLines([.init(text: "x", confidence: 1, boundingBox: CGRect(x: 0.2, y: 0.7, width: 0.3, height: 0.1))])
        XCTAssertEqual(lines[0].rect.minY, 0.2, accuracy: 0.0001)
    }

    private func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let context = CGContext(directory.appendingPathComponent("input.pdf") as CFURL, mediaBox: &box, nil)!
        for _ in 0..<2 { context.beginPDFPage(nil); context.endPDFPage() }
        context.closePDF()
        return directory
    }
}

private struct MarkdownLayoutStub: LayoutAnalyzing {
    func regions(for image: CGImage) throws -> [LayoutRegion] {
        [.init(query: 0, label: "doc_title", score: 1, rect: CGRect(x: 0, y: 0.1, width: 1, height: 0.3)),
         .init(query: 1, label: "table", score: 1, rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.4))]
    }
}
private struct MarkdownTextRecognizer: TextRecognizing {
    func recognize(image: CGImage, languages: [String], recognitionLevel: OCRRecognitionLevel, usesLanguageCorrection: Bool) throws -> [RecognizedTextBox] {
        [.init(text: "한글 제목", confidence: 1, boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.7, height: 0.1))]
    }
}
private struct MarkdownTableStub: TableRecognizing {
    func markdown(for image: CGImage, languages: [String], usesLanguageCorrection: Bool) throws -> String? {
        "| 표 |\n| --- |\n| 내용 |"
    }
}
private struct NeverRender: PDFRendering {
    func render(page: CGPDFPage, scale: OCRRenderScale) throws -> RenderedPDFPage { XCTFail("render before model load"); throw AppleVisionOCRError.pdfFailure("unexpected render") }
}
private struct NeverRecognize: TextRecognizing {
    func recognize(image: CGImage, languages: [String], recognitionLevel: OCRRecognitionLevel, usesLanguageCorrection: Bool) throws -> [RecognizedTextBox] { XCTFail("OCR before model load"); return [] }
}
