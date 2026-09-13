import AppKit
import AppleVisionOCRCore

final class VOCRAppDelegate: NSObject, NSApplicationDelegate {
    private let files: [URL]
    private let progressStore = ProgressStore()
    private let statusItemController = StatusItemController()
    private var windowController: VOCRWindowController?
    private var jobController: OCRJobController?

    init(arguments: [String]) {
        self.files = arguments
            .map { URL(fileURLWithPath: $0) }
            .filter { $0.pathExtension.lowercased() == "pdf" }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let windowController = VOCRWindowController(files: files)
        let jobController = OCRJobController(files: files)

        self.windowController = windowController
        self.jobController = jobController

        wire(windowController: windowController, jobController: jobController)
        NSApp.setActivationPolicy(.accessory)
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        if files.isEmpty {
            windowController.appendLog(VOCRStrings.logSelectPDFInFinder.text)
        } else if Self.headlessMode != nil {
            startHeadless(jobController: jobController)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func wire(windowController: VOCRWindowController, jobController: OCRJobController) {
        windowController.onStart = { [weak jobController] selection, parallelism, recognitionLevel, renderScale, usesLanguageCorrection, shouldRunInBackground in
            if shouldRunInBackground {
                NSApp.setActivationPolicy(.accessory)
            } else {
                NSApp.setActivationPolicy(.accessory)
                NSApp.activate(ignoringOtherApps: true)
            }
            jobController?.start(
                selection: selection,
                parallelism: parallelism,
                recognitionLevel: recognitionLevel,
                renderScale: renderScale,
                usesLanguageCorrection: usesLanguageCorrection
            )
        }
        windowController.onPause = { [weak jobController] in
            jobController?.pause()
        }
        windowController.onResume = { [weak jobController] in
            jobController?.resume()
        }
        windowController.onCancel = { [weak jobController] in
            jobController?.cancel()
        }
        windowController.onParallelismChange = { [weak jobController] parallelism in
            jobController?.updateParallelism(parallelism)
        }
        windowController.onWindowWillClose = {
            NSApp.setActivationPolicy(.accessory)
        }
        windowController.onQuit = {
            NSApp.terminate(nil)
        }

        jobController.onProgress = { [weak self, weak windowController] snapshot in
            windowController?.updateProgress(snapshot)
            self?.statusItemController.update(snapshot)
            self?.progressStore.write(snapshot)
        }
        jobController.onLog = { [weak windowController] message in
            windowController?.appendLog(message)
        }
        jobController.onOutput = { [weak windowController] output in
            windowController?.noteOutput(output)
        }
        jobController.onFinish = { [weak windowController] state in
            windowController?.finish(state)
            if Self.headlessMode != nil {
                NSApp.terminate(nil)
            } else if VOCRAppLifecyclePolicy.shouldTerminateAfterFinish(state) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NSApp.terminate(nil)
                }
            }
        }

        statusItemController.onShowWindow = { [weak windowController] in
            windowController?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        statusItemController.onPause = { [weak jobController] in
            jobController?.pause()
        }
        statusItemController.onResume = { [weak jobController] in
            jobController?.resume()
        }
        statusItemController.onCancel = { [weak jobController] in
            jobController?.cancel()
        }
    }

    // Test seam: VOCR_HEADLESS triggers an automatic run. "1"/"pdf" → searchable PDF;
    // "txt-pagebreaks" → page-divided TXT (split page-break path);
    // "cancel" → cancel mid-run; "pause" → pause then resume mid-run.
    private static var headlessMode: String? {
        guard let value = ProcessInfo.processInfo.environment["VOCR_HEADLESS"], !value.isEmpty else {
            return nil
        }
        return value
    }

    private func startHeadless(jobController: OCRJobController) {
        do {
            let mode = Self.headlessMode ?? "1"
            let wantsTextPageBreaks = mode == "txt-pagebreaks"
            let selection = try OCRJobOutputSelection(
                writesText: wantsTextPageBreaks,
                writesPDF: !wantsTextPageBreaks,
                includesPageBreaks: wantsTextPageBreaks
            )
            let parallelism = try OCRJobParallelism(count: VOCRWindowController.defaultWorkerCount)
            jobController.start(
                selection: selection,
                parallelism: parallelism,
                recognitionLevel: .accurate,
                renderScale: .quality,
                usesLanguageCorrection: true
            )
            switch mode {
            case "cancel":
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    Self.headlessLog("cancel requested")
                    jobController.cancel()
                }
            case "pause":
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    Self.headlessLog("pause requested")
                    jobController.pause()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    Self.headlessLog("resume requested")
                    jobController.resume()
                }
            default:
                break
            }
        } catch {
            jobController.onLog(error.localizedDescription)
            NSApp.terminate(nil)
        }
    }

    private static func headlessLog(_ message: String) {
        FileHandle.standardError.write(Data("VOCR-HEADLESS: \(message)\n".utf8))
    }
}
