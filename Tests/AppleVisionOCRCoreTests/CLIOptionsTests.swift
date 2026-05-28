import XCTest
@testable import AppleVisionOCRCore

final class CLIOptionsTests: XCTestCase {
    func testMissingInputIsInvalidUsage() {
        XCTAssertThrowsError(try CLIOptions.parse([])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testUnsupportedArgumentIsInvalidUsage() {
        XCTAssertThrowsError(try CLIOptions.parse(["input.pdf", "--unknown"])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testParsesRunDefaults() throws {
        let options = try CLIOptions.parse(["/tmp/input.pdf"])

        XCTAssertEqual(options.inputURL.path, "/tmp/input.pdf")
        XCTAssertEqual(options.outputURL?.path, "/tmp/input_ocr.pdf")
        XCTAssertNil(options.txtOutputURL)
        XCTAssertEqual(options.outputMode, .searchablePDF)
        XCTAssertEqual(options.languages, ["ko", "en"])
        XCTAssertEqual(options.recognitionLevel, .accurate)
        XCTAssertEqual(options.pageParallelism, .default)
        XCTAssertEqual(options.renderScale, .quality)
        XCTAssertNil(options.pageRange)
        XCTAssertNil(options.splitWorkers)
        XCTAssertFalse(options.dryRun)
    }

    func testParsesOutputLanguageRecognitionParallelismRenderScaleAndDryRun() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--output", "/tmp/custom.pdf",
            "--lang", "ko, en",
            "--recognition-level", "accurate",
            "--page-parallelism", "16",
            "--render-scale", "1.5",
            "--dry-run"
        ])

        XCTAssertEqual(options.outputURL?.path, "/tmp/custom.pdf")
        XCTAssertEqual(options.languages, ["ko", "en"])
        XCTAssertEqual(options.recognitionLevel, .accurate)
        XCTAssertEqual(options.pageParallelism.count, 16)
        XCTAssertEqual(options.renderScale, .balanced)
        XCTAssertTrue(options.dryRun)
    }

    func testFastRecognitionRequiresSupportedLanguages() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--lang", "en",
            "--recognition-level", "fast"
        ])

        XCTAssertEqual(options.languages, ["en"])
        XCTAssertEqual(options.recognitionLevel, .fast)
    }

    func testFastRecognitionRejectsDefaultKoreanLanguageSet() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--recognition-level", "fast"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testInvalidPageParallelismIsInvalidUsage() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--page-parallelism", "0"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testNonNumericPageParallelismIsInvalidUsage() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--page-parallelism", "many"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testInvalidRenderScaleIsInvalidUsage() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--render-scale", "0.5"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testParsesDefaultTextOutputWithPageBreaks() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt",
            "--page-breaks"
        ])

        XCTAssertEqual(options.outputURL?.path, "/tmp/input_ocr.pdf")
        XCTAssertEqual(options.txtOutputURL?.path, "/tmp/input.txt")
        XCTAssertTrue(options.outputMode.writesPDF)
        XCTAssertTrue(options.outputMode.writesText)
        XCTAssertTrue(options.outputMode.includesPageBreaks)
        XCTAssertTrue(options.includePageBreaks)
    }

    func testParsesExplicitTextOutput() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-output", "/tmp/custom.txt"
        ])

        XCTAssertEqual(options.outputURL?.path, "/tmp/input_ocr.pdf")
        XCTAssertEqual(options.txtOutputURL?.path, "/tmp/custom.txt")
        XCTAssertEqual(options.outputMode, .textAndSearchablePDF)
        XCTAssertFalse(options.includePageBreaks)
    }

    func testParsesTextOnlyWithDefaultTextOutputAndPageBreaks() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-only",
            "--page-breaks"
        ])

        XCTAssertNil(options.outputURL)
        XCTAssertEqual(options.txtOutputURL?.path, "/tmp/input.txt")
        XCTAssertEqual(options.outputMode, .pageDividedText)
        XCTAssertTrue(options.includePageBreaks)
    }

    func testParsesTextOnlyWithExplicitTextOutput() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-only",
            "--txt-output", "/tmp/custom.txt"
        ])

        XCTAssertNil(options.outputURL)
        XCTAssertEqual(options.txtOutputURL?.path, "/tmp/custom.txt")
        XCTAssertEqual(options.outputMode, .plainText)
    }

    func testParsesSplitWorkersForTextOnly() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-only",
            "--txt-output", "/tmp/custom.txt",
            "--split-workers", "4"
        ])

        XCTAssertEqual(options.splitWorkers, 4)
    }

    func testParsesPageRangeForTextOnly() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-only",
            "--txt-output", "/tmp/custom.txt",
            "--page-range", "101-200"
        ])

        XCTAssertEqual(options.pageRange, 101...200)
    }

    func testPageBreaksRequireTextOutput() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--page-breaks"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testTextOnlyCannotBeCombinedWithPDFOutput() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-only",
            "--output", "/tmp/custom.pdf"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testSplitWorkersRequireTextOnly() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt",
            "--split-workers", "4"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testSplitWorkersRejectPageBreaks() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-only",
            "--page-breaks",
            "--split-workers", "4"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testPageRangeRequiresTextOnly() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt",
            "--page-range", "1-10"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testTextOnlyAndDefaultTextOutputAreMutuallyExclusive() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-only",
            "--txt"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testTextOutputModesAreMutuallyExclusive() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt",
            "--txt-output", "/tmp/custom.txt"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testExistingOutputIsRefusedDuringValidation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("input.pdf")
        let output = directory.appendingPathComponent("input_ocr.pdf")
        FileManager.default.createFile(atPath: input.path, contents: Data("%PDF-1.4\n".utf8))
        FileManager.default.createFile(atPath: output.path, contents: Data())

        let options = try CLIOptions.parse([input.path])

        XCTAssertThrowsError(try options.validateFileSystem()) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .outputAlreadyExists)
        }
    }

    func testExistingTextOutputIsRefusedDuringValidation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("input.pdf")
        let textOutput = directory.appendingPathComponent("input.txt")
        FileManager.default.createFile(atPath: input.path, contents: Data("%PDF-1.4\n".utf8))
        FileManager.default.createFile(atPath: textOutput.path, contents: Data())

        let options = try CLIOptions.parse([
            input.path,
            "--txt"
        ])

        XCTAssertThrowsError(try options.validateFileSystem()) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .outputAlreadyExists)
        }
    }

    func testTextOnlyValidationIgnoresExistingDefaultPDFOutput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("input.pdf")
        let output = directory.appendingPathComponent("input_ocr.pdf")
        FileManager.default.createFile(atPath: input.path, contents: Data("%PDF-1.4\n".utf8))
        FileManager.default.createFile(atPath: output.path, contents: Data())

        let options = try CLIOptions.parse([
            input.path,
            "--txt-only"
        ])

        XCTAssertNoThrow(try options.validateFileSystem())
    }
}
