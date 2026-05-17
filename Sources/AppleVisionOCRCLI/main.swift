import Foundation
import AppleVisionOCRCore

let runner = CommandRunner()
let exitCode = runner.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitCode.rawValue)
