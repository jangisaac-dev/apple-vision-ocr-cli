@testable import AppleVisionOCRCore
import CoreGraphics
import XCTest
@testable import VOCR

final class OCRJobControllerResilienceTests: XCTestCase {
    func testLockIsExclusiveAndReleased() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("job.lock")
        let first = try VOCRJobLock(url: url)
        let second = try VOCRJobLock(url: url)

        XCTAssertTrue(try first.tryAcquire())
        XCTAssertFalse(try second.tryAcquire())
        first.release()
        XCTAssertTrue(try second.tryAcquire())
        second.release()
    }

    func testFailedPDFDoesNotStopNextFileAndCountsOnlySuccesses() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bad = directory.appendingPathComponent("broken.pdf")
        let good = directory.appendingPathComponent("good.pdf")
        let missing = directory.appendingPathComponent("missing.pdf")
        let original = Data("not a PDF".utf8)
        try original.write(to: bad)
        try makePDF(at: good)
        let controller = OCRJobController(
            files: [bad, good, missing],
            pipeline: SearchablePDFPipeline(recognizer: StubRecognizer()),
            jobLockURL: directory.appendingPathComponent("job.lock")
        )
        let finished = expectation(description: "batch finished")
        var snapshots: [VOCRProgressSnapshot] = []
        var logs: [String] = []
        controller.onProgress = { snapshots.append($0) }
        controller.onLog = { logs.append($0) }
        controller.onFinish = { state in
            XCTAssertEqual(state, .failed)
            finished.fulfill()
        }

        try start(controller)
        wait(for: [finished], timeout: 30)

        XCTAssertEqual(snapshots.last?.completedFiles, 1)
        XCTAssertEqual(snapshots.last?.message, VOCRStrings.messageOCRJobFailed(["broken.pdf", "missing.pdf"]))
        XCTAssertTrue(logs.contains { $0.hasPrefix("broken.pdf:") })
        XCTAssertTrue(logs.contains { $0.hasPrefix("missing.pdf:") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("good.txt").path))
        XCTAssertEqual(try Data(contentsOf: bad), original)
    }

    func testPipelineFailureDoesNotCancelRemainingFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        try makePDF(at: first)
        try makePDF(at: second)
        let controller = OCRJobController(
            files: [first, second],
            pipeline: SearchablePDFPipeline(recognizer: StubRecognizer(failsFirst: true)),
            jobLockURL: directory.appendingPathComponent("job.lock")
        )
        let finished = expectation(description: "pipeline failure recovered")
        var finalSnapshot: VOCRProgressSnapshot?
        controller.onProgress = { finalSnapshot = $0 }
        controller.onFinish = { state in
            XCTAssertEqual(state, .failed)
            finished.fulfill()
        }

        try start(controller)
        wait(for: [finished], timeout: 5)

        XCTAssertEqual(finalSnapshot?.completedFiles, 1)
        XCTAssertEqual(finalSnapshot?.message, VOCRStrings.messageOCRJobFailed(["first.pdf"]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("second.txt").path))
    }

    func testCancelWhileWaitingDoesNotPrepareOrProcessFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent("job.lock")
        let owner = try VOCRJobLock(url: lockURL)
        XCTAssertTrue(try owner.tryAcquire())
        defer { owner.release() }
        let input = directory.appendingPathComponent("missing.pdf")
        let controller = OCRJobController(files: [input], jobLockURL: lockURL)
        let finished = expectation(description: "waiting canceled")
        var logs: [String] = []
        var sawWaiting = false
        controller.onLog = { logs.append($0) }
        controller.onOutput = { _ in XCTFail("Output must not be prepared while waiting") }
        controller.onProgress = { snapshot in
            if snapshot.message == VOCRStrings.messageWaitingForJob.text {
                sawWaiting = true
                controller.cancel()
            }
        }
        controller.onFinish = { state in
            XCTAssertEqual(state, .canceled)
            finished.fulfill()
        }

        try start(controller)
        wait(for: [finished], timeout: 5)

        XCTAssertTrue(sawWaiting)
        XCTAssertFalse(logs.contains { $0.contains(input.lastPathComponent) })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["job.lock"])
        XCTAssertFalse(try VOCRJobLock(url: lockURL).tryAcquire())
    }

    private func start(_ controller: OCRJobController) throws {
        controller.start(
            selection: try OCRJobOutputSelection(writesText: true, writesPDF: false, includesPageBreaks: false),
            parallelism: .serial,
            recognitionLevel: .accurate,
            renderScale: .quality,
            usesLanguageCorrection: true
        )
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vocr-resilience-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePDF(at url: URL) throws {
        var bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.endPDFPage()
        context.closePDF()
    }
}

private final class StubRecognizer: TextRecognizing {
    private var failsFirst: Bool

    init(failsFirst: Bool = false) { self.failsFirst = failsFirst }

    func recognize(
        image: CGImage,
        languages: [String],
        recognitionLevel: OCRRecognitionLevel,
        usesLanguageCorrection: Bool
    ) throws -> [RecognizedTextBox] {
        if failsFirst {
            failsFirst = false
            throw AppleVisionOCRError.pdfFailure("injected OCR failure")
        }
        return []
    }
}
