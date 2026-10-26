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
        XCTAssertTrue(options.usesLanguageCorrection)
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
            "--no-language-correction",
            "--dry-run"
        ])

        XCTAssertEqual(options.outputURL?.path, "/tmp/custom.pdf")
        XCTAssertEqual(options.languages, ["ko", "en"])
        XCTAssertEqual(options.recognitionLevel, .accurate)
        XCTAssertEqual(options.pageParallelism.count, 16)
        XCTAssertEqual(options.renderScale, .balanced)
        XCTAssertFalse(options.usesLanguageCorrection)
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

    func testParsesSplitWorkersForPDFOnly() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--output", "/tmp/out.pdf",
            "--split-workers", "4"
        ])

        XCTAssertEqual(options.splitWorkers, 4)
        XCTAssertTrue(options.outputMode.writesPDF)
        XCTAssertFalse(options.outputMode.writesText)
    }

    func testParsesSplitWorkersUpperBoundForTextOnly() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-only",
            "--txt-output", "/tmp/custom.txt",
            "--split-workers", "16"
        ])

        XCTAssertEqual(options.splitWorkers, 16)
    }

    func testSplitWorkersRejectsAboveUpperBound() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-only",
            "--txt-output", "/tmp/custom.txt",
            "--split-workers", "17"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testSplitWorkersRejectsBelowLowerBound() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-only",
            "--txt-output", "/tmp/custom.txt",
            "--split-workers", "1"
        ])) { error in
            XCTAssertEqual((error as? AppleVisionOCRError)?.exitCode, .invalidUsage)
        }
    }

    func testParsesSplitWorkersForCombinedTextAndPDF() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-output", "/tmp/x.txt",
            "--split-workers", "4"
        ])

        XCTAssertEqual(options.splitWorkers, 4)
        XCTAssertEqual(options.outputURL?.path, "/tmp/input_ocr.pdf")
        XCTAssertEqual(options.txtOutputURL?.path, "/tmp/x.txt")
        XCTAssertEqual(options.outputMode, .textAndSearchablePDF)
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

    func testParsesPageRangeForPDFOnly() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--output", "/tmp/out.pdf",
            "--page-range", "2-5"
        ])

        XCTAssertEqual(options.pageRange, 2...5)
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

    func testSplitWorkersAllowCombinedDefaultTextAndPDF() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt",
            "--split-workers", "4"
        ])

        XCTAssertEqual(options.splitWorkers, 4)
        XCTAssertEqual(options.outputMode, .textAndSearchablePDF)
    }

    func testSplitWorkersAllowPageBreaksWithTextOnly() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt-only",
            "--page-breaks",
            "--split-workers", "4"
        ])

        XCTAssertEqual(options.splitWorkers, 4)
        XCTAssertTrue(options.includePageBreaks)
        XCTAssertEqual(options.outputMode, .pageDividedText)
    }

    func testPageRangeAllowsCombinedTextAndPDF() throws {
        let options = try CLIOptions.parse([
            "/tmp/input.pdf",
            "--txt",
            "--page-range", "1-10"
        ])

        XCTAssertEqual(options.pageRange, 1...10)
        XCTAssertEqual(options.outputMode, .textAndSearchablePDF)
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
    func testMarkdownOutputFlags() throws {
        for flags in [["--md-only"], ["--md-output", "/tmp/custom.md"], ["--md-only", "--md-output", "/tmp/custom.md"]] {
            let options = try CLIOptions.parse(["/tmp/input.pdf"] + flags)
            XCTAssertEqual(options.outputMode, .markdown)
            XCTAssertNil(options.outputURL)
            XCTAssertNil(options.txtOutputURL)
            XCTAssertNil(options.mdPagesOutputURL)
            XCTAssertEqual(options.mdOutputURL?.path, flags.contains("/tmp/custom.md") ? "/tmp/custom.md" : "/tmp/input.md")
        }
        let options = try CLIOptions.parse(["/tmp/input.pdf", "--md-pages-output", "/tmp/pages.json"])
        XCTAssertEqual(options.outputMode, .markdown)
        XCTAssertNil(options.mdOutputURL)
        XCTAssertNil(options.outputURL)
        XCTAssertEqual(options.mdPagesOutputURL?.path, "/tmp/pages.json")
    }

    func testMarkdownRejectsOtherOutputFlagsInEitherOrder() {
        let conflicting = [["--output", "/tmp/out.pdf"], ["--txt"], ["--txt-only"], ["--txt-output", "/tmp/out.txt"], ["--page-breaks"]]
        for markdown in [["--md-only"], ["--md-output", "/tmp/out.md"], ["--md-pages-output", "/tmp/pages.json"]] {
            for other in conflicting {
                for flags in [markdown + other, other + markdown] {
                    XCTAssertThrowsError(try CLIOptions.parse(["/tmp/input.pdf"] + flags)) {
                        XCTAssertEqual(($0 as? AppleVisionOCRError)?.exitCode, .invalidUsage)
                    }
                }
            }
        }
        for other in [["--md-only"], ["--md-output", "/tmp/out.md"], ["--split-workers", "2"]] {
            XCTAssertThrowsError(try CLIOptions.parse(["/tmp/input.pdf", "--md-pages-output", "/tmp/pages.json"] + other))
        }
        XCTAssertNoThrow(try CLIOptions.parse(["/tmp/input.pdf", "--md-only", "--split-workers", "2"]))
    }

    func testMarkdownFileSystemValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.pdf")
        try Data("%PDF-1.4\n".utf8).write(to: input)
        for (flag, filename) in [("--md-output", "input.md"), ("--md-pages-output", "pages.json")] {
            let output = directory.appendingPathComponent(filename)
            let options = try CLIOptions.parse([input.path, flag, output.path])
            XCTAssertNoThrow(try options.validateFileSystem())
            try Data().write(to: output)
            XCTAssertThrowsError(try options.validateFileSystem()) {
                XCTAssertEqual(($0 as? AppleVisionOCRError)?.exitCode, .outputAlreadyExists)
            }
            let invalid = try CLIOptions.parse([input.path, flag, directory.appendingPathComponent("out.txt").path])
            XCTAssertThrowsError(try invalid.validateFileSystem()) {
                XCTAssertEqual(($0 as? AppleVisionOCRError)?.exitCode, .invalidUsage)
            }
            let missingParent = try CLIOptions.parse([input.path, flag, directory.appendingPathComponent("missing/" + filename).path])
            XCTAssertThrowsError(try missingParent.validateFileSystem()) {
                XCTAssertEqual(($0 as? AppleVisionOCRError)?.exitCode, .inputFileProblem)
            }
        }
    }

}
