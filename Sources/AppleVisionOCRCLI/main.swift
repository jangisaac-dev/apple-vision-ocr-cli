import Foundation
import Darwin
import AppleVisionOCRCore

// The parent passes its own PID rather than letting the child snapshot getppid(): if the parent
// dies before the child reaches this line, a snapshot would record the reaper as the "parent" and
// the watchdog would never fire.
if let rawParentProcessID = ProcessInfo.processInfo.environment["APPLE_VISION_OCR_PARENT_PID"],
   let parentProcessID = pid_t(rawParentProcessID) {
    // SIGSTOP pauses the child watchdog too, so parent death while paused can still leak a child.
    DispatchQueue.global(qos: .utility).async {
        while true {
            if getppid() != parentProcessID {
                exit(ExitCode.pdfFailure.rawValue)
            }
            sleep(1)
        }
    }
}

let runner = CommandRunner()
let exitCode = runner.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitCode.rawValue)
