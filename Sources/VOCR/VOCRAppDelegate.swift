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
            windowController.appendLog("Finder에서 PDF 파일을 선택한 뒤 Apple Vision OCR을 실행하세요.")
        } else if ProcessInfo.processInfo.environment["VOCR_HEADLESS"] == "1" {
            startHeadless(jobController: jobController)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func wire(windowController: VOCRWindowController, jobController: OCRJobController) {
        windowController.onStart = { [weak jobController] selection, parallelism, recognitionLevel, renderScale, shouldRunInBackground in
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
                renderScale: renderScale
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
            if ProcessInfo.processInfo.environment["VOCR_HEADLESS"] == "1" {
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

    private func startHeadless(jobController: OCRJobController) {
        do {
            let selection = try OCRJobOutputSelection(
                writesText: false,
                writesPDF: true,
                includesPageBreaks: false
            )
            let parallelism = try OCRJobParallelism(count: VOCRWindowController.defaultWorkerCount)
            jobController.start(
                selection: selection,
                parallelism: parallelism,
                recognitionLevel: .accurate,
                renderScale: .quality
            )
        } catch {
            jobController.onLog(error.localizedDescription)
            NSApp.terminate(nil)
        }
    }
}
