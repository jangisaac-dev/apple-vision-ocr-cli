import Foundation
import Darwin
import AppleVisionOCRCore

final class SignalCancellation {
    private let control: OCRJobControl
    private let lock = NSLock()
    private var signalExitCode: Int32?

    init(control: OCRJobControl) {
        self.control = control
    }

    var exitCode: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return signalExitCode
    }

    func handle(signal: Int32, occurrences: UInt = 1) {
        for _ in 0..<max(1, occurrences) {
            lock.lock()
            let isFirstSignal = signalExitCode == nil
            if isFirstSignal {
                signalExitCode = 128 + signal
            }
            lock.unlock()

            if isFirstSignal {
                control.cancel()
            } else {
                exit(128 + signal)
            }
        }
    }
}

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

let control = OCRJobControl()
let signalCancellation = SignalCancellation(control: control)
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)

let signalQueue = DispatchQueue(label: "apple-vision-ocr.signal", qos: .utility)
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
sigintSource.setEventHandler {
    signalCancellation.handle(signal: SIGINT, occurrences: sigintSource.data)
}
sigtermSource.setEventHandler {
    signalCancellation.handle(signal: SIGTERM, occurrences: sigtermSource.data)
}
sigintSource.resume()
sigtermSource.resume()

let runner = CommandRunner()
let exitCode = runner.run(arguments: Array(CommandLine.arguments.dropFirst()), control: control)
sigintSource.cancel()
sigtermSource.cancel()
if let signalExitCode = signalCancellation.exitCode {
    exit(signalExitCode)
}
exit(exitCode.rawValue)
