import CoreGraphics
import Foundation
import XCTest
import AppleVisionOCRCore
@testable import AppleVisionOCRCLI

final class CommandRunnerTests: XCTestCase {
    func testHelpReturnsSuccessAndPrintsUsage() {
        var output: [String] = []
        let runner = CommandRunner(
            stdout: { output.append($0) },
            stderr: { _ in }
        )

        let exitCode = runner.run(arguments: ["--help"])

        XCTAssertEqual(exitCode, .success)
        XCTAssertTrue(output.joined(separator: "\n").contains("Usage:"))
        XCTAssertTrue(output.joined(separator: "\n").contains("--render-scale"))
    }

    func testHelpListsOutputContractAndExitCodes() {
        var output: [String] = []
        let runner = CommandRunner(
            stdout: { output.append($0) },
            stderr: { _ in }
        )

        _ = runner.run(arguments: ["--help"])

        let help = output.joined(separator: "\n")
        XCTAssertTrue(help.contains("Output:"))
        XCTAssertTrue(help.contains("stdout = written output paths only"))
        XCTAssertTrue(help.contains("stderr = logs"))
        XCTAssertTrue(help.contains("Progress: N/M pages"))
        XCTAssertTrue(help.contains("error: <message>"))
        XCTAssertTrue(help.contains("Exit codes:"))
        XCTAssertTrue(help.contains("0   success"))
        XCTAssertTrue(help.contains("1   invalid usage"))
        XCTAssertTrue(help.contains("2   input file problem"))
        XCTAssertTrue(help.contains("3   PDF/OCR failure"))
        XCTAssertTrue(help.contains("4   Vision failure"))
        XCTAssertTrue(help.contains("5   output already exists"))
        XCTAssertTrue(help.contains("130 canceled by SIGINT"))
        XCTAssertTrue(help.contains("143 canceled by SIGTERM"))
    }

    func testSplitTextRunReportsOneProgressLinePerCompletedPage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input.pdf")
        let outputURL = directory.appendingPathComponent("output.txt")
        try makePDF(at: inputURL, pageCount: 3)
        let workerURL = try makeProgressWorker(in: directory)
        let stderr = Locked<[String]>([])
        let runner = CommandRunner(
            stdout: { _ in },
            stderr: { message in stderr.withValue { $0.append(message) } },
            executableURL: workerURL
        )

        let exitCode = runner.run(arguments: [
            inputURL.path,
            "--txt-only",
            "--txt-output", outputURL.path,
            "--split-workers", "2",
            "--page-range", "2-3"
        ])

        XCTAssertEqual(exitCode, .success)
        XCTAssertEqual(
            stderr.value.filter { $0.hasPrefix("Progress:") },
            ["Progress: 1/2 pages", "Progress: 2/2 pages"]
        )
        XCTAssertEqual(try String(contentsOf: outputURL), "chunk-2-2\nchunk-3-3")
    }

    func testVersionReturnsSuccessAndPrintsVersion() {
        var output: [String] = []
        let runner = CommandRunner(
            stdout: { output.append($0) },
            stderr: { _ in }
        )

        let exitCode = runner.run(arguments: ["--version"])

        XCTAssertEqual(exitCode, .success)
        XCTAssertEqual(output, ["apple-vision-ocr \(CommandRunner.version)"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommandRunnerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makePDF(at url: URL, pageCount: Int) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "CommandRunnerTests", code: 1)
        }
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func makeProgressWorker(in directory: URL) throws -> URL {
        let workerURL = directory.appendingPathComponent("worker.sh")
        let script = #"""
        #!/bin/sh
        set -eu
        output=
        range=
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --output|--txt-output)
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
        printf 'chunk-%s' "$range" > "$output"
        page=${range%-*}
        end=${range#*-}
        while [ "$page" -le "$end" ]; do
            printf 'Completed page %s\n' "$page" >&2
            page=$((page + 1))
        done
        """#
        try script.write(to: workerURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workerURL.path)
        return workerURL
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storedValue)
    }
}
