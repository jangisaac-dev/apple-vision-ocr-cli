import CoreGraphics
import XCTest
@testable import AppleVisionOCRCore

final class SplitProcessOCRRunnerTests: XCTestCase {
    func testPlanChunksEvenlyAcrossWorkers() {
        let chunks = SplitProcessOCRRunner.planChunks(pageCount: 24, workerCount: 12)

        XCTAssertEqual(chunks, [
            1...2,
            3...4,
            5...6,
            7...8,
            9...10,
            11...12,
            13...14,
            15...16,
            17...18,
            19...20,
            21...22,
            23...24
        ])
        XCTAssertEqual(Array(chunks.joined()), Array(1...24))
    }

    func testPlanChunksDistributesRemainderToFirstWorkers() {
        let chunks = SplitProcessOCRRunner.planChunks(pageCount: 23, workerCount: 5)

        XCTAssertEqual(chunks.map(\.count), [5, 5, 5, 4, 4])
        XCTAssertEqual(chunks, [
            1...5,
            6...10,
            11...15,
            16...19,
            20...23
        ])
    }

    func testMergePDFsCombinesAllPages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.pdf")
        let secondURL = directory.appendingPathComponent("second.pdf")
        let outputURL = directory.appendingPathComponent("merged.pdf")
        try makePDF(at: firstURL, pageCount: 2)
        try makePDF(at: secondURL, pageCount: 3)

        try SplitProcessOCRRunner.mergePDFs([firstURL, secondURL], to: outputURL)

        let mergedDocument = try XCTUnwrap(CGPDFDocument(outputURL as CFURL))
        XCTAssertEqual(mergedDocument.numberOfPages, 5)
    }

    func testWriteCombinedTextJoinsChunksWithNewlines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.txt")
        let secondURL = directory.appendingPathComponent("second.txt")
        let outputURL = directory.appendingPathComponent("combined.txt")
        try "first chunk".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second chunk".write(to: secondURL, atomically: true, encoding: .utf8)

        try SplitProcessOCRRunner.writeCombinedText([firstURL, secondURL], to: outputURL)

        let combined = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertEqual(combined, "first chunk\nsecond chunk")
    }

    func testWriteCombinedTextRefusesToReplaceExistingOutput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let chunkURL = directory.appendingPathComponent("chunk.txt")
        let outputURL = directory.appendingPathComponent("combined.txt")
        try "new text".write(to: chunkURL, atomically: true, encoding: .utf8)
        try "existing text".write(to: outputURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try SplitProcessOCRRunner.writeCombinedText([chunkURL], to: outputURL)) { error in
            XCTAssertEqual(
                error as? AppleVisionOCRError,
                .outputAlreadyExists("output already exists: \(outputURL.path)")
            )
        }
        XCTAssertEqual(try String(contentsOf: outputURL, encoding: .utf8), "existing text")
    }

    func testCombinedOutputRefusesToReplaceExistingPDFOrText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("input.pdf")
        let pdfOutputURL = directory.appendingPathComponent("output.pdf")
        let textOutputURL = directory.appendingPathComponent("output.txt")
        let runner = SplitProcessOCRRunner(executableURL: directory.appendingPathComponent("unused-worker"))
        try makePDF(at: inputURL, pageCount: 1)

        for existingURL in [pdfOutputURL, textOutputURL] {
            try Data().write(to: existingURL)
            XCTAssertThrowsError(try runner.run(
                inputURL: inputURL,
                output: .searchablePDFAndText(pdf: pdfOutputURL, text: textOutputURL),
                workerCount: 2,
                languages: ["en"],
                recognitionLevel: .fast,
                renderScale: .compact
            )) { error in
                XCTAssertEqual(
                    error as? AppleVisionOCRError,
                    .outputAlreadyExists("output already exists: \(existingURL.path)")
                )
            }
            try FileManager.default.removeItem(at: existingURL)
        }
    }

    private func makePDF(at url: URL, pageCount: Int) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            XCTFail("failed to create PDF")
            return
        }

        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
            context.endPDFPage()
        }
        context.closePDF()
    }
}
