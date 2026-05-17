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
}
