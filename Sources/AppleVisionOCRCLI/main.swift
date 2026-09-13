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

    // Later signals are ignored: exiting here would skip the runner's cleanup (temp dir, workers).
    // SIGKILL remains the way to force an exit.
    func handle(signal: Int32) {
        lock.lock()
        let isFirstSignal = signalExitCode == nil
        if isFirstSignal {
            signalExitCode = 128 + signal
        }
        lock.unlock()

        if isFirstSignal {
            control.cancel()
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
var signalSources: [DispatchSourceSignal] = []

// Split children keep the default SIGTERM/SIGINT action: the parent owns cleanup and escalates
// to SIGKILL after 2 s, so a graceful child cancel would only add delay.
if ProcessInfo.processInfo.environment["APPLE_VISION_OCR_PARENT_PID"] == nil {
    let signalQueue = DispatchQueue(label: "apple-vision-ocr.signal", qos: .utility)
    for signalNumber in [SIGINT, SIGTERM] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
        source.setEventHandler {
            signalCancellation.handle(signal: signalNumber)
        }
        source.resume()
        signalSources.append(source)
    }
}

let runner = CommandRunner()
let exitCode = runner.run(arguments: Array(CommandLine.arguments.dropFirst()), control: control)
signalSources.forEach { $0.cancel() }
// A signal that lands after the outputs were written does not undo a successful run.
if exitCode != .success, let signalExitCode = signalCancellation.exitCode {
    exit(signalExitCode)
}
exit(exitCode.rawValue)
