import CoreGraphics
import Darwin
import Foundation
import XCTest
@testable import AppleVisionOCRCore

final class SplitProcessOCRRunnerProcessTests: XCTestCase {
    private var previousChildParallelism: String?

    override func setUp() {
        super.setUp()
        previousChildParallelism = environmentValue("APPLE_VISION_OCR_SPLIT_CHILD_PAGE_PARALLELISM")
        unsetenv("APPLE_VISION_OCR_SPLIT_CHILD_PAGE_PARALLELISM")
    }

    override func tearDown() {
        restoreEnvironment(
            "APPLE_VISION_OCR_SPLIT_CHILD_PAGE_PARALLELISM",
            to: previousChildParallelism
        )
        super.tearDown()
    }

    func testRunMergesTextReportsProgressAndPassesExactTextArguments() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let outputURL = directory.appendingPathComponent("output.txt")
        try makePDF(at: inputURL, pageCount: 3)
        let plannedRanges = SplitProcessOCRRunner.planChunks(pageCount: 3, workerCount: 2).map {
            "\($0.lowerBound)-\($0.upperBound)"
        }
        let workerURL = try makeWorker(in: directory, body: """
        if [ "$range" = "3-3" ]; then sleep 0.1; fi
        printf 'chunk-%s' "$range" > "$output"
        page=${range%-*}
        end=${range#*-}
        while [ "$page" -le "$end" ]; do
            printf 'Completed page %s\\n' "$page" >&2
            page=$((page + 1))
        done
        """)
        let progress = Locked<[SplitProcessOCRRunner.ProgressUpdate]>([])

        try SplitProcessOCRRunner(executableURL: workerURL).run(
            inputURL: inputURL,
            output: .text(outputURL),
            workerCount: 2,
            languages: ["ko", "en"],
            recognitionLevel: .fast,
            renderScale: .balanced,
            usesLanguageCorrection: false,
            includePageBreaks: false
        ) { update in
            progress.withValue { $0.append(update) }
        }

        XCTAssertEqual(try String(contentsOf: outputURL), "chunk-1-2\nchunk-3-3")
        XCTAssertEqual(progress.value.map(\.completedPages), [1, 2, 3])
        XCTAssertEqual(Set(progress.value.map(\.totalPages)), [3])
        try assertInvocations(in: directory, expectedRanges: plannedRanges)
        try assertTextArguments(
            in: directory, inputURL: inputURL, range: "1-2", chunk: 0,
            usesLanguageCorrection: false, includesPageBreaks: false
        )
        try assertTextArguments(
            in: directory, inputURL: inputURL, range: "3-3", chunk: 1,
            usesLanguageCorrection: false, includesPageBreaks: false
        )
        try assertRecordedProcessesExited(in: directory)
    }

    func testRunCountsOnlyRealStderrProgressMarkersAndCapsAtTotal() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let outputURL = directory.appendingPathComponent("output.txt")
        try makePDF(at: inputURL, pageCount: 3)
        let workerURL = try makeWorker(in: directory, body: """
        printf '%s\\n' "$support_dir/Completed page stdout-path"
        printf 'stderr mentions Completed page in a path\\n' >&2
        printf 'chunk-%s' "$range" > "$output"
        page=${range%-*}
        end=${range#*-}
        while [ "$page" -le "$end" ]; do
            printf 'Completed page %s\\n' "$page" >&2
            page=$((page + 1))
        done
        """)
        let progress = Locked<[SplitProcessOCRRunner.ProgressUpdate]>([])

        try SplitProcessOCRRunner(executableURL: workerURL).run(
            inputURL: inputURL,
            output: .text(outputURL),
            workerCount: 2,
            languages: ["en"],
            recognitionLevel: .fast,
            renderScale: .compact
        ) { update in
            progress.withValue { $0.append(update) }
        }

        XCTAssertEqual(try String(contentsOf: outputURL), "chunk-1-2\nchunk-3-3")
        XCTAssertEqual(progress.value.map(\.completedPages), [1, 2, 3])
        XCTAssertTrue(progress.value.allSatisfy { $0.completedPages <= $0.totalPages })
        XCTAssertEqual(Set(progress.value.map(\.totalPages)), [3])
        try assertRecordedProcessesExited(in: directory)
    }

    func testRunMergesOutputBeforeDescendantClosesInheritedPipes() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let outputURL = directory.appendingPathComponent("output.txt")
        let descendantPIDURL = directory.appendingPathComponent("descendant.pid")
        try makePDF(at: inputURL, pageCount: 1)
        let workerURL = try makeWorker(in: directory, body: """
        sleep 30 &
        descendant=$!
        printf '%s\\n' "$descendant" > "$support_dir/descendant.pid"
        printf 'chunk-output' > "$output"
        """)
        let outcome = Locked<Result<Void, Error>?>(nil)
        let runDuration = Locked<TimeInterval?>(nil)
        let finished = expectation(description: "split run returns while descendant holds pipes")
        let startedAt = Date()

        DispatchQueue.global().async {
            do {
                try SplitProcessOCRRunner(executableURL: workerURL).run(
                    inputURL: inputURL,
                    output: .text(outputURL),
                    workerCount: 2,
                    languages: ["en"],
                    recognitionLevel: .fast,
                    renderScale: .compact
                )
                outcome.withValue { $0 = .success(()) }
            } catch {
                outcome.withValue { $0 = .failure(error) }
            }
            runDuration.withValue { $0 = Date().timeIntervalSince(startedAt) }
            finished.fulfill()
        }

        XCTAssertTrue(waitForFile(at: descendantPIDURL, timeout: 1), "descendant PID was not recorded")
        guard let descendantPID = try? Int32(
            String(contentsOf: descendantPIDURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            return XCTFail("descendant PID was not readable")
        }
        defer { _ = kill(descendantPID, SIGKILL) }

        wait(for: [finished], timeout: 10)
        guard let duration = runDuration.value else {
            _ = kill(descendantPID, SIGKILL)
            let cleanupDeadline = Date().addingTimeInterval(2)
            while runDuration.value == nil && Date() < cleanupDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            return XCTFail("split run did not return within 10 seconds")
        }
        XCTAssertLessThan(duration, 10)
        guard case .success = outcome.value else {
            return XCTFail("expected split run to succeed")
        }
        XCTAssertEqual(try String(contentsOf: outputURL), "chunk-output")
        try assertRecordedProcessesExited(in: directory)
    }

    func testRunPassesPageBreaksWhenRequested() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let outputURL = directory.appendingPathComponent("output.txt")
        try makePDF(at: inputURL, pageCount: 1)
        let plannedRanges = SplitProcessOCRRunner.planChunks(pageCount: 1, workerCount: 2).map {
            "\($0.lowerBound)-\($0.upperBound)"
        }
        let workerURL = try makeWorker(in: directory, body: "printf 'text' > \"$output\"")

        try SplitProcessOCRRunner(executableURL: workerURL).run(
            inputURL: inputURL,
            output: .text(outputURL),
            workerCount: 2,
            languages: ["ko", "en"],
            recognitionLevel: .fast,
            renderScale: .balanced,
            includePageBreaks: true
        )

        try assertInvocations(in: directory, expectedRanges: plannedRanges)
        try assertTextArguments(
            in: directory, inputURL: inputURL, range: "1-1", chunk: 0,
            usesLanguageCorrection: true, includesPageBreaks: true
        )
        try assertRecordedProcessesExited(in: directory)
    }

    func testRunSplitsOnlyTheRequestedPageRange() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let outputURL = directory.appendingPathComponent("output.txt")
        try makePDF(at: inputURL, pageCount: 5)
        let workerURL = try makeWorker(in: directory, body: """
        printf 'chunk-%s' "$range" > "$output"
        page=${range%-*}
        end=${range#*-}
        while [ "$page" -le "$end" ]; do
            printf 'Completed page %s\\n' "$page" >&2
            page=$((page + 1))
        done
        """)
        let progress = Locked<[SplitProcessOCRRunner.ProgressUpdate]>([])

        try SplitProcessOCRRunner(executableURL: workerURL).run(
            inputURL: inputURL,
            output: .text(outputURL),
            workerCount: 2,
            languages: ["ko", "en"],
            recognitionLevel: .fast,
            renderScale: .balanced,
            pageRange: 2...4
        ) { update in
            progress.withValue { $0.append(update) }
        }

        XCTAssertEqual(try String(contentsOf: outputURL), "chunk-2-3\nchunk-4-4")
        XCTAssertEqual(Set(progress.value.map(\.totalPages)), [3])
        try assertInvocations(in: directory, expectedRanges: ["2-3", "4-4"])
        XCTAssertThrowsError(
            try SplitProcessOCRRunner(executableURL: workerURL).run(
                inputURL: inputURL,
                output: .text(directory.appendingPathComponent("out-of-range.txt")),
                workerCount: 2,
                languages: ["ko", "en"],
                recognitionLevel: .fast,
                renderScale: .balanced,
                pageRange: 4...6
            )
        )
    }

    func testRunPassesConfiguredChildParallelismAndEnvironment() throws {
        let previousQueueCapacity = environmentValue("APPLE_VISION_OCR_QUEUE_CAPACITY")
        setenv("APPLE_VISION_OCR_QUEUE_CAPACITY", "7", 1)
        setenv("APPLE_VISION_OCR_SPLIT_CHILD_PAGE_PARALLELISM", "3", 1)
        defer {
            restoreEnvironment("APPLE_VISION_OCR_QUEUE_CAPACITY", to: previousQueueCapacity)
        }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let outputURL = directory.appendingPathComponent("output.txt")
        try makePDF(at: inputURL, pageCount: 1)
        let workerURL = try makeWorker(in: directory, body: "printf 'text' > \"$output\"")

        try SplitProcessOCRRunner(executableURL: workerURL).run(
            inputURL: inputURL,
            output: .text(outputURL),
            workerCount: 2,
            languages: ["en"],
            recognitionLevel: .fast,
            renderScale: .compact
        )

        let arguments = try recordedArguments(in: directory, range: "1-1")
        XCTAssertEqual(arguments.filter { $0 == "--page-parallelism" }.count, 1)
        XCTAssertEqual(value(after: "--page-parallelism", in: arguments), "3")
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent("env/1-1"), encoding: .utf8),
            "7\n\(ProcessInfo.processInfo.processIdentifier)\n"
        )
        try assertRecordedProcessesExited(in: directory)
    }

    func testRunPassesExactSearchablePDFArguments() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let outputURL = directory.appendingPathComponent("output.pdf")
        try makePDF(at: inputURL, pageCount: 1)
        let plannedRanges = SplitProcessOCRRunner.planChunks(pageCount: 1, workerCount: 2).map {
            "\($0.lowerBound)-\($0.upperBound)"
        }
        let workerURL = try makeWorker(in: directory, body: "cp \"$input\" \"$output\"")

        try SplitProcessOCRRunner(executableURL: workerURL).run(
            inputURL: inputURL,
            output: .searchablePDF(outputURL),
            workerCount: 2,
            languages: ["en"],
            recognitionLevel: .accurate,
            renderScale: .quality
        )

        let arguments = try recordedArguments(in: directory, range: "1-1")
        let chunkOutput = try XCTUnwrap(arguments[safe: 2])
        XCTAssertEqual(arguments, [
            inputURL.path, "--output", chunkOutput,
            "--lang", "en", "--recognition-level", "accurate",
            "--render-scale", "2.0", "--page-range", "1-1"
        ])
        XCTAssertEqual(URL(fileURLWithPath: chunkOutput).lastPathComponent, "chunk-0.pdf")
        XCTAssertEqual(URL(fileURLWithPath: chunkOutput).deletingLastPathComponent().lastPathComponent, "out")
        XCTAssertEqual(CGPDFDocument(outputURL as CFURL)?.numberOfPages, 1)
        try assertInvocations(in: directory, expectedRanges: plannedRanges)
        try assertRecordedProcessesExited(in: directory)
    }

    func testRunMergesCombinedOutputInPageOrderAndPassesExactArguments() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let pdfOutputURL = directory.appendingPathComponent("output.pdf")
        let textOutputURL = directory.appendingPathComponent("output.txt")
        try makePDF(at: inputURL, pageCount: 3)
        try makePDF(at: directory.appendingPathComponent("chunk-1-2.pdf"), pageWidths: [101, 102])
        try makePDF(at: directory.appendingPathComponent("chunk-3-3.pdf"), pageWidths: [103])
        let workerURL = try makeWorker(in: directory, body: """
        cp "$support_dir/chunk-$range.pdf" "$pdf_output"
        printf 'chunk-%s' "$range" > "$text_output"
        """)

        try SplitProcessOCRRunner(executableURL: workerURL).run(
            inputURL: inputURL,
            output: .searchablePDFAndText(pdf: pdfOutputURL, text: textOutputURL),
            workerCount: 2,
            languages: ["ko", "en"],
            recognitionLevel: .fast,
            renderScale: .balanced,
            usesLanguageCorrection: false,
            includePageBreaks: true
        )

        XCTAssertEqual(try String(contentsOf: textOutputURL), "chunk-1-2\nchunk-3-3")
        let mergedPDF = try XCTUnwrap(CGPDFDocument(pdfOutputURL as CFURL))
        let pageWidths = (1...mergedPDF.numberOfPages).compactMap {
            mergedPDF.page(at: $0)?.getBoxRect(.mediaBox).width
        }
        XCTAssertEqual(pageWidths, [101, 102, 103])
        try assertCombinedArguments(in: directory, inputURL: inputURL, range: "1-2", chunk: 0)
        try assertCombinedArguments(in: directory, inputURL: inputURL, range: "3-3", chunk: 1)
        try assertRecordedProcessesExited(in: directory)
    }

    func testCombinedOutputRemovesPDFWhenTextWriteFails() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let pdfOutputURL = directory.appendingPathComponent("output.pdf")
        let textOutputURL = directory.appendingPathComponent("missing/output.txt")
        try makePDF(at: inputURL, pageCount: 1)
        let workerURL = try makeWorker(in: directory, body: """
        cp "$input" "$pdf_output"
        printf 'text' > "$text_output"
        """)

        XCTAssertThrowsError(try SplitProcessOCRRunner(executableURL: workerURL).run(
            inputURL: inputURL,
            output: .searchablePDFAndText(pdf: pdfOutputURL, text: textOutputURL),
            workerCount: 2,
            languages: ["en"],
            recognitionLevel: .fast,
            renderScale: .compact
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdfOutputURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: textOutputURL.path))
    }

    func testRunPropagatesFailureForceKillsSiblingAndRemovesOutputAndTemporaryDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let outputURL = directory.appendingPathComponent("output.txt")
        try makePDF(at: inputURL, pageCount: 2)
        let workerURL = try makeWorker(in: directory, body: """
        if [ "$range" = "2-2" ]; then
            trap '' TERM
            : > "$support_dir/sibling-ready"
            while :; do :; done
        fi
        while [ ! -f "$support_dir/sibling-ready" ]; do :; done
        printf 'partial' > "$output"
        printf 'deliberate worker failure detail\\n' >&2
        exit 1
        """)
        let splitDirectoriesBefore = splitTemporaryDirectories()

        // Run off the main thread behind an expectation: if shutdown ever regresses to an
        // unbounded wait, this test must FAIL rather than hang the whole suite.
        let outcome = Locked<Result<Void, Error>?>(nil)
        let finished = expectation(description: "failing split run returns")
        DispatchQueue.global().async {
            do {
                try SplitProcessOCRRunner(executableURL: workerURL).run(
                    inputURL: inputURL,
                    output: .text(outputURL),
                    workerCount: 2,
                    languages: ["en"],
                    recognitionLevel: .fast,
                    renderScale: .compact
                )
                outcome.withValue { $0 = .success(()) }
            } catch {
                outcome.withValue { $0 = .failure(error) }
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 10)
        guard case .failure(let error) = outcome.value else {
            return XCTFail("expected worker failure to propagate")
        }
        XCTAssertEqual(
            error as? AppleVisionOCRError,
            .pdfFailure("split worker 0 failed: deliberate worker failure detail")
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(splitTemporaryDirectories(), splitDirectoriesBefore)
        try assertInvocations(in: directory, expectedRanges: ["1-1", "2-2"])
        try assertRecordedProcessesExited(in: directory)
    }

    func testCancelDuringSplitRunRemovesTemporaryDirectoryAndOutput() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let outputURL = directory.appendingPathComponent("output.txt")
        try makePDF(at: inputURL, pageCount: 1)
        let workerURL = try makeWorker(in: directory, body: """
        sleep 30 &
        sleeper=$!
        trap 'kill "$sleeper" 2>/dev/null || true; exit 0' TERM INT
        wait "$sleeper"
        """)
        let control = OCRJobControl()
        let result = Locked<Result<Void, Error>?>(nil)
        let finished = expectation(description: "canceled split run returns")
        let splitDirectoriesBefore = splitTemporaryDirectories()

        DispatchQueue.global().async {
            do {
                try SplitProcessOCRRunner(executableURL: workerURL).run(
                    inputURL: inputURL,
                    output: .text(outputURL),
                    workerCount: 2,
                    languages: ["en"],
                    recognitionLevel: .fast,
                    renderScale: .compact,
                    control: control
                )
                result.withValue { $0 = .success(()) }
            } catch {
                result.withValue { $0 = .failure(error) }
            }
            finished.fulfill()
        }

        XCTAssertTrue(
            waitForFile(at: directory.appendingPathComponent("pids/1-1"), timeout: 1),
            "worker PID was not recorded"
        )
        control.cancel()
        wait(for: [finished], timeout: 4)

        guard case .failure(let error) = result.value else {
            return XCTFail("expected cancellation failure")
        }
        XCTAssertEqual(error as? AppleVisionOCRError, .pdfFailure("OCR job canceled"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(splitTemporaryDirectories(), splitDirectoriesBefore)
        try assertRecordedProcessesExited(in: directory)
    }

    func testCancelWhilePausedReturnsPromptlyWithoutOutputOrSurvivingWorker() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let outputURL = directory.appendingPathComponent("output.txt")
        try makePDF(at: inputURL, pageCount: 1)
        let workerURL = try makeWorker(in: directory, body: """
        trap '' TERM
        while :; do :; done
        """)
        let control = OCRJobControl()
        let result = Locked<Result<Void, Error>?>(nil)
        let finished = expectation(description: "canceled split run returns")
        let splitDirectoriesBefore = splitTemporaryDirectories()

        DispatchQueue.global().async {
            do {
                try SplitProcessOCRRunner(executableURL: workerURL).run(
                    inputURL: inputURL,
                    output: .text(outputURL),
                    workerCount: 2,
                    languages: ["en"],
                    recognitionLevel: .fast,
                    renderScale: .compact,
                    control: control
                )
                result.withValue { $0 = .success(()) }
            } catch {
                result.withValue { $0 = .failure(error) }
            }
            finished.fulfill()
        }

        let pidURL = directory.appendingPathComponent("pids/1-1")
        XCTAssertTrue(waitForFile(at: pidURL, timeout: 1), "worker PID was not recorded")
        // Pause only after the child has recorded its PID: pausing before run() SIGSTOPs the
        // worker within ~50ms of spawn, often before the shell reaches its own bookkeeping.
        control.pause()
        // Assert the worker really reached the stopped state. Without this the test passes even if
        // pause() does nothing at all, since it would only be checking that cancel returns promptly.
        let workerPID = try XCTUnwrap(Int32(
            try String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        XCTAssertTrue(
            waitForProcessState("T", pid: workerPID, timeout: 2),
            "worker never entered the stopped (T) state, so pause did not take effect"
        )
        let cancelTime = Date()
        control.cancel()
        wait(for: [finished], timeout: 4)

        XCTAssertLessThan(Date().timeIntervalSince(cancelTime), 3)
        guard case .failure(let error) = result.value else {
            return XCTFail("expected cancellation failure")
        }
        XCTAssertEqual(error as? AppleVisionOCRError, .pdfFailure("OCR job canceled"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(splitTemporaryDirectories(), splitDirectoriesBefore)
        try assertRecordedProcessesExited(in: directory)
    }

    private func waitForProcessState(_ expected: String, pid: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-o", "stat=", "-p", String(pid)]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return false }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let state = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if state.hasPrefix(expected) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SplitProcessOCRRunnerProcessTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeWorker(in directory: URL, body: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("args"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("pids"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("env"), withIntermediateDirectories: true
        )
        let workerURL = directory.appendingPathComponent("worker.sh")
        let script = """
        #!/bin/sh
        set -eu
        support_dir=$(dirname "$0")
        printf '%s\\n' "$*" >> "$support_dir/invocations.log"
        raw="$support_dir/args/$$.raw"
        printf '%s\\n' "$@" > "$raw"
        input=$1
        shift
        range=
        output=
        pdf_output=
        text_output=
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --output)
                    pdf_output=$2
                    output=$2
                    shift 2
                    ;;
                --txt-output)
                    text_output=$2
                    output=$2
                    shift 2
                    ;;
                --page-range)
                    range=$2
                    shift 2
                    ;;
                *)
                    shift
                    ;;
            esac
        done
        mv "$raw" "$support_dir/args/$range"
        printf '%s\\n' "$$" > "$support_dir/pids/$range"
        printf '%s\\n%s\\n' "${APPLE_VISION_OCR_QUEUE_CAPACITY-}" "${APPLE_VISION_OCR_PARENT_PID-}" > "$support_dir/env/$range"
        \(body)
        """
        try script.write(to: workerURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workerURL.path)
        return workerURL
    }

    private func assertTextArguments(
        in directory: URL,
        inputURL: URL,
        range: String,
        chunk: Int,
        usesLanguageCorrection: Bool,
        includesPageBreaks: Bool
    ) throws {
        let arguments = try recordedArguments(in: directory, range: range)
        let chunkOutput = try XCTUnwrap(arguments[safe: 3])
        var expected = [
            inputURL.path, "--txt-only", "--txt-output", chunkOutput,
            "--lang", "ko,en", "--recognition-level", "fast",
            "--render-scale", "1.5", "--page-range", range
        ]
        if !usesLanguageCorrection {
            expected.append("--no-language-correction")
        }
        if includesPageBreaks {
            expected.append("--page-breaks")
        }
        XCTAssertEqual(arguments, expected)
        XCTAssertEqual(URL(fileURLWithPath: chunkOutput).lastPathComponent, "chunk-\(chunk).txt")
        XCTAssertEqual(URL(fileURLWithPath: chunkOutput).deletingLastPathComponent().lastPathComponent, "out")
    }

    private func assertCombinedArguments(
        in directory: URL,
        inputURL: URL,
        range: String,
        chunk: Int
    ) throws {
        let arguments = try recordedArguments(in: directory, range: range)
        let pdfChunkOutput = try XCTUnwrap(arguments[safe: 2])
        let textChunkOutput = try XCTUnwrap(arguments[safe: 4])
        XCTAssertEqual(arguments, [
            inputURL.path,
            "--output", pdfChunkOutput,
            "--txt-output", textChunkOutput,
            "--lang", "ko,en",
            "--recognition-level", "fast",
            "--render-scale", "1.5",
            "--page-range", range,
            "--no-language-correction",
            "--page-breaks"
        ])
        XCTAssertEqual(URL(fileURLWithPath: pdfChunkOutput).lastPathComponent, "chunk-\(chunk).pdf")
        XCTAssertEqual(URL(fileURLWithPath: textChunkOutput).lastPathComponent, "chunk-\(chunk).txt")
        XCTAssertEqual(
            URL(fileURLWithPath: pdfChunkOutput).deletingLastPathComponent(),
            URL(fileURLWithPath: textChunkOutput).deletingLastPathComponent()
        )
    }

    private func recordedArguments(in directory: URL, range: String) throws -> [String] {
        try String(contentsOf: directory.appendingPathComponent("args/\(range)"), encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    private func assertInvocations(in directory: URL, expectedRanges: [String]) throws {
        let invocations = try String(
            contentsOf: directory.appendingPathComponent("invocations.log"), encoding: .utf8
        ).split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
        XCTAssertEqual(invocations.count, expectedRanges.count)
        XCTAssertEqual(
            invocations.compactMap { value(after: "--page-range", in: $0) }.sorted(),
            expectedRanges.sorted()
        )
    }

    private func assertRecordedProcessesExited(in directory: URL) throws {
        let pidDirectory = directory.appendingPathComponent("pids")
        for pidURL in try FileManager.default.contentsOfDirectory(
            at: pidDirectory, includingPropertiesForKeys: nil
        ) {
            let pid = try XCTUnwrap(pid_t(String(contentsOf: pidURL).trimmingCharacters(in: .whitespacesAndNewlines)))
            errno = 0
            XCTAssertEqual(kill(pid, 0), -1, "worker \(pid) is still alive")
            XCTAssertEqual(errno, ESRCH, "worker \(pid) was not reaped")
        }
    }

    private func splitTemporaryDirectories() -> Set<String> {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: FileManager.default.temporaryDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return Set(urls.map(\.lastPathComponent).filter { $0.hasPrefix("apple-vision-ocr-split-") })
    }

    private func waitForFile(at url: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option) else {
            return nil
        }
        return arguments[safe: arguments.index(after: index)]
    }

    private func environmentValue(_ key: String) -> String? {
        getenv(key).map { String(cString: $0) }
    }

    private func restoreEnvironment(_ key: String, to value: String?) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }

    private func makePDF(at url: URL, pageCount: Int) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func makePDF(at url: URL, pageWidths: [CGFloat]) throws {
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: nil, nil))
        for width in pageWidths {
            var mediaBox = CGRect(x: 0, y: 0, width: width, height: 100)
            let pageInfo = withUnsafeBytes(of: &mediaBox) { bytes -> CFDictionary in
                [kCGPDFContextMediaBox as String: Data(bytes)] as CFDictionary
            }
            context.beginPDFPage(pageInfo)
            context.endPDFPage()
        }
        context.closePDF()
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.withLock { storedValue }
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.withLock { body(&storedValue) }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
