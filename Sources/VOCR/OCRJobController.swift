import AppleVisionOCRCore
import CoreGraphics
import Foundation

enum VOCRRunState: String, Codable {
    case idle
    case running
    case paused
    case completed
    case failed
    case canceled
}

struct VOCRProgressSnapshot {
    let state: VOCRRunState
    let currentFile: String?
    let completedFiles: Int
    let totalFiles: Int
    let completedPages: Int
    let totalPages: Int
    let percent: Int
    let message: String
}

struct VOCRJobOutput {
    let inputURL: URL
    let pdfOutputURL: URL?
    let textOutputURL: URL?
}

final class OCRJobController {
    var onProgress: (VOCRProgressSnapshot) -> Void = { _ in }
    var onLog: (String) -> Void = { _ in }
    var onFinish: (VOCRRunState) -> Void = { _ in }
    var onOutput: (VOCRJobOutput) -> Void = { _ in }

    private let files: [URL]
    private let pipeline: SearchablePDFPipeline
    private var control = OCRJobControl()
    private var state: VOCRRunState = .idle
    private var isRunning = false
    private var lastSnapshot: VOCRProgressSnapshot?
    private let parallelismLock = NSLock()
    private var activeParallelism = OCRJobParallelism.default
    private var parallelismLimiter: OCRParallelismLimiter?
    private lazy var cliExecutableURL: URL? = Self.resolveCLIExecutableURL()
    private lazy var splitRunner: SplitProcessOCRRunner? = {
        guard let cliExecutableURL else {
            return nil
        }
        return SplitProcessOCRRunner(executableURL: cliExecutableURL)
    }()

    private struct PreparedJob {
        let index: Int
        let inputURL: URL
        let output: VOCRJobOutput
    }

    private struct ProgressAggregate {
        var completedFiles: Int
        var pageProgress: [Int]
        let totalPages: Int
    }

    init(files: [URL], pipeline: SearchablePDFPipeline = SearchablePDFPipeline()) {
        self.files = files
        self.pipeline = pipeline
    }

    func start(
        selection: OCRJobOutputSelection,
        parallelism: OCRJobParallelism,
        recognitionLevel: OCRRecognitionLevel,
        renderScale: OCRRenderScale,
        usesLanguageCorrection: Bool
    ) {
        guard !isRunning else {
            return
        }
        guard !files.isEmpty else {
            finish(state: .failed, message: VOCRStrings.messageNoPDFSelected.text)
            return
        }

        isRunning = true
        state = .running
        control = OCRJobControl()
        setActiveParallelism(parallelism)
        emit(snapshot: snapshot(
            state: .running,
            currentFile: nil,
            completedFiles: 0,
            completedPageBase: 0,
            totalPageCount: 0,
            event: nil,
            message: VOCRStrings.messageJobStarted.text
        ))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.run(
                selection: selection,
                recognitionLevel: recognitionLevel,
                renderScale: renderScale,
                usesLanguageCorrection: usesLanguageCorrection
            )
        }
    }

    func updateParallelism(_ parallelism: OCRJobParallelism) {
        setActiveParallelism(parallelism)
        if isRunning {
            log(VOCRStrings.logWorkerCountChanged(parallelism.count))
            emit(snapshot: snapshotFromLast(
                state: state,
                message: VOCRStrings.messageWorkerCount(parallelism.count)
            ))
        }
    }

    func pause() {
        guard state == .running else {
            return
        }
        state = .paused
        control.pause()
        emit(snapshot: snapshotFromLast(
            state: .paused,
            message: VOCRStrings.messagePauseRequested.text
        ))
    }

    func resume() {
        guard state == .paused else {
            return
        }
        state = .running
        control.resume()
        emit(snapshot: snapshotFromLast(
            state: .running,
            message: VOCRStrings.buttonResume.text
        ))
    }

    func cancel() {
        guard isRunning else {
            return
        }
        state = .canceled
        control.cancel()
        parallelismLock.withLock {
            parallelismLimiter?.wakeWaiters()
        }
        emit(snapshot: snapshotFromLast(
            state: .canceled,
            message: VOCRStrings.messageCancelRequested.text
        ))
    }

    private func run(
        selection: OCRJobOutputSelection,
        recognitionLevel: OCRRecognitionLevel,
        renderScale: OCRRenderScale,
        usesLanguageCorrection: Bool
    ) {
        do {
            let pageCounts = try files.map { try pageCount(for: $0) }
            let totalPageCount = pageCounts.reduce(0, +)
            let jobs = try prepareJobs(selection: selection)
            let aggregateLock = NSLock()
            let pageLimiter = OCRParallelismLimiter(parallelism: currentParallelism())
            installLimiter(pageLimiter)
            defer {
                clearLimiter(pageLimiter)
            }
            var aggregate = ProgressAggregate(
                completedFiles: 0,
                pageProgress: Array(repeating: 0, count: jobs.count),
                totalPages: totalPageCount
            )
            var firstError: Error?

            for job in jobs {
                if control.isCanceled {
                    break
                }

                do {
                    let workerCount = currentParallelism().count
                    let canUseSplitRunner = splitRunner != nil
                        && workerCount > 1

                    if splitRunner == nil {
                        log(VOCRStrings.logCLINotFoundSingleProcess.text)
                    }

                    let jobOptions = try OCRJobOptions(
                        inputURL: job.inputURL,
                        pdfOutputURL: job.output.pdfOutputURL,
                        textOutputURL: job.output.textOutputURL,
                        outputMode: selection.outputMode,
                        recognitionLevel: recognitionLevel,
                        pageParallelism: currentParallelism(),
                        renderScale: renderScale,
                        usesLanguageCorrection: usesLanguageCorrection
                    )

                    log(VOCRStrings.logFileStarted(job.inputURL.lastPathComponent))
                    emitOutput(job.output)

                    if canUseSplitRunner, let splitRunner {
                        try splitRunner.run(
                            inputURL: job.inputURL,
                            output: splitOutput(for: job.output, selection: selection),
                            workerCount: workerCount,
                            languages: jobOptions.languages,
                            recognitionLevel: recognitionLevel,
                            renderScale: renderScale,
                            usesLanguageCorrection: usesLanguageCorrection,
                            includePageBreaks: selection.includesPageBreaks,
                            control: control
                        ) { [weak self] update in
                            guard let self else {
                                return
                            }
                            let snapshot = aggregateLock.withLock {
                                aggregate.pageProgress[job.index] = update.completedPages
                                return self.snapshot(
                                    state: self.state,
                                    currentFile: job.inputURL.lastPathComponent,
                                    aggregate: aggregate,
                                    event: nil,
                                    message: "OCR \(job.inputURL.lastPathComponent)"
                                )
                            }
                            self.emit(snapshot: snapshot)
                        }
                    } else {
                        try pipeline.run(job: jobOptions, control: control, pageLimiter: pageLimiter) { [weak self] event in
                            guard let self else {
                                return
                            }
                            let snapshot = aggregateLock.withLock {
                                aggregate.pageProgress[job.index] = event.completedPages
                                return self.snapshot(
                                    state: self.state,
                                    currentFile: job.inputURL.lastPathComponent,
                                    aggregate: aggregate,
                                    event: event,
                                    message: event.message
                                )
                            }
                            self.emit(snapshot: snapshot)
                        }
                    }

                    let completionSnapshot = aggregateLock.withLock {
                        aggregate.completedFiles += 1
                        aggregate.pageProgress[job.index] = pageCounts[job.index]
                        return snapshot(
                            state: state,
                            currentFile: job.inputURL.lastPathComponent,
                            aggregate: aggregate,
                            event: nil,
                            message: VOCRStrings.messageFileCompleted(job.inputURL.lastPathComponent)
                        )
                    }
                    emit(snapshot: completionSnapshot)
                    log(VOCRStrings.messageFileCompleted(job.inputURL.lastPathComponent))
                } catch {
                    firstError = error
                    control.cancel()
                    pageLimiter.wakeWaiters()
                    break
                }
            }

            if let firstError {
                let finalState: VOCRRunState = state == .canceled ? .canceled : .failed
                finish(state: finalState, message: errorMessage(firstError))
            } else if control.isCanceled || state == .canceled {
                finish(state: .canceled, message: "OCR job canceled")
            } else {
                finish(state: .completed, message: VOCRStrings.messageOCRJobCompleted.text)
            }
        } catch {
            let finalState: VOCRRunState = control.isCanceled || state == .canceled ? .canceled : .failed
            finish(state: finalState, message: errorMessage(error))
        }
    }

    private func splitOutput(for output: VOCRJobOutput, selection: OCRJobOutputSelection) throws -> SplitProcessOCRRunner.Output {
        if selection.writesPDF,
           selection.writesText,
           let pdfOutputURL = output.pdfOutputURL,
           let textOutputURL = output.textOutputURL {
            return .searchablePDFAndText(pdf: pdfOutputURL, text: textOutputURL)
        }
        if selection.writesPDF, let pdfOutputURL = output.pdfOutputURL {
            return .searchablePDF(pdfOutputURL)
        }
        if selection.writesText, let textOutputURL = output.textOutputURL {
            return .text(textOutputURL)
        }
        throw OCRJobOptionError.missingOutput
    }

    private static func resolveCLIExecutableURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleExecutableURL: URL? = Bundle.main.executableURL,
        fileManager: FileManager = .default
    ) -> URL? {
        if let path = environment["VOCR_CLI_PATH"], fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let siblingURL = bundleExecutableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("apple-vision-ocr"),
           fileManager.isExecutableFile(atPath: siblingURL.path) {
            return siblingURL
        }

        let localBinURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/apple-vision-ocr")
        if fileManager.isExecutableFile(atPath: localBinURL.path) {
            return localBinURL
        }

        for directory in environment["PATH", default: ""].split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent("apple-vision-ocr")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private func setActiveParallelism(_ parallelism: OCRJobParallelism) {
        parallelismLock.withLock {
            activeParallelism = parallelism
            parallelismLimiter?.updateLimit(parallelism)
        }
    }

    private func currentParallelism() -> OCRJobParallelism {
        parallelismLock.withLock {
            activeParallelism
        }
    }

    private func installLimiter(_ limiter: OCRParallelismLimiter) {
        parallelismLock.withLock {
            limiter.updateLimit(activeParallelism)
            parallelismLimiter = limiter
        }
    }

    private func clearLimiter(_ limiter: OCRParallelismLimiter) {
        parallelismLock.withLock {
            if parallelismLimiter === limiter {
                parallelismLimiter = nil
            }
        }
    }

    private func prepareJobs(selection: OCRJobOutputSelection) throws -> [PreparedJob] {
        var reservedPaths = Set<String>()

        return try files.enumerated().map { index, inputURL in
            let pdfOutputURL: URL?
            let textOutputURL: URL?

            if selection.writesPDF {
                let defaultURL = try OutputPathResolver.defaultOutputURL(for: inputURL)
                pdfOutputURL = availableURL(defaultURL, reservedPaths: &reservedPaths)
            } else {
                pdfOutputURL = nil
            }

            if selection.writesText {
                let defaultURL = try OutputPathResolver.defaultTextOutputURL(for: inputURL)
                textOutputURL = availableURL(defaultURL, reservedPaths: &reservedPaths)
            } else {
                textOutputURL = nil
            }

            let output = VOCRJobOutput(inputURL: inputURL, pdfOutputURL: pdfOutputURL, textOutputURL: textOutputURL)
            return PreparedJob(index: index, inputURL: inputURL, output: output)
        }
    }

    private func availableURL(_ defaultURL: URL, reservedPaths: inout Set<String>) -> URL {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: defaultURL.path), !reservedPaths.contains(defaultURL.path) {
            reservedPaths.insert(defaultURL.path)
            return defaultURL
        }

        let directory = defaultURL.deletingLastPathComponent()
        let baseName = defaultURL.deletingPathExtension().lastPathComponent
        let pathExtension = defaultURL.pathExtension

        var counter = 1
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName)(\(counter))")
                .appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: candidate.path), !reservedPaths.contains(candidate.path) {
                reservedPaths.insert(candidate.path)
                return candidate
            }
            counter += 1
        }
    }

    private func snapshot(
        state: VOCRRunState,
        currentFile: String?,
        completedFiles: Int,
        completedPageBase: Int,
        totalPageCount: Int,
        event: OCRProgressEvent?,
        message: String
    ) -> VOCRProgressSnapshot {
        let aggregateCompletedPages = completedPageBase + (event?.completedPages ?? 0)
        let aggregateTotalPages = totalPageCount > 0 ? totalPageCount : event?.totalPages ?? 0
        let overallPercent: Int
        if aggregateTotalPages == 0 {
            overallPercent = 0
        } else {
            overallPercent = min(100, (aggregateCompletedPages * 100) / aggregateTotalPages)
        }

        return VOCRProgressSnapshot(
            state: state,
            currentFile: currentFile ?? event?.currentFile,
            completedFiles: completedFiles,
            totalFiles: files.count,
            completedPages: aggregateCompletedPages,
            totalPages: aggregateTotalPages,
            percent: overallPercent,
            message: message
        )
    }

    private func snapshot(
        state: VOCRRunState,
        currentFile: String?,
        aggregate: ProgressAggregate,
        event: OCRProgressEvent?,
        message: String
    ) -> VOCRProgressSnapshot {
        let completedPages = aggregate.pageProgress.reduce(0, +)
        let percent: Int
        if aggregate.totalPages == 0 {
            percent = 0
        } else {
            percent = min(100, (completedPages * 100) / aggregate.totalPages)
        }

        return VOCRProgressSnapshot(
            state: state,
            currentFile: currentFile ?? event?.currentFile,
            completedFiles: aggregate.completedFiles,
            totalFiles: files.count,
            completedPages: completedPages,
            totalPages: aggregate.totalPages,
            percent: percent,
            message: message
        )
    }

    private func pageCount(for url: URL) throws -> Int {
        guard let document = CGPDFDocument(url as CFURL) else {
            throw AppleVisionOCRError.pdfFailure("failed to open input PDF: \(url.path)")
        }
        guard document.numberOfPages > 0 else {
            throw AppleVisionOCRError.pdfFailure("input PDF has no pages: \(url.path)")
        }
        return document.numberOfPages
    }

    private func emit(snapshot: VOCRProgressSnapshot) {
        lastSnapshot = snapshot
        DispatchQueue.main.async { [onProgress] in
            onProgress(snapshot)
        }
    }

    private func emitOutput(_ output: VOCRJobOutput) {
        DispatchQueue.main.async { [onOutput] in
            onOutput(output)
        }
    }

    private func log(_ message: String) {
        DispatchQueue.main.async { [onLog] in
            onLog(message)
        }
    }

    private func finish(state finalState: VOCRRunState, message: String) {
        isRunning = false
        state = finalState
        log(message)
        if finalState == .completed {
            emit(snapshot: snapshot(
                state: finalState,
                currentFile: nil,
                completedFiles: files.count,
                completedPageBase: lastSnapshot?.totalPages ?? 0,
                totalPageCount: lastSnapshot?.totalPages ?? 0,
                event: nil,
                message: message
            ))
        } else {
            emit(snapshot: snapshotFromLast(state: finalState, message: message))
        }
        DispatchQueue.main.async { [onFinish] in
            onFinish(finalState)
        }
    }

    private func snapshotFromLast(state: VOCRRunState, message: String) -> VOCRProgressSnapshot {
        if let lastSnapshot {
            return VOCRProgressSnapshot(
                state: state,
                currentFile: lastSnapshot.currentFile,
                completedFiles: lastSnapshot.completedFiles,
                totalFiles: lastSnapshot.totalFiles,
                completedPages: lastSnapshot.completedPages,
                totalPages: lastSnapshot.totalPages,
                percent: lastSnapshot.percent,
                message: message
            )
        }

        return snapshot(
            state: state,
            currentFile: nil,
            completedFiles: 0,
            completedPageBase: 0,
            totalPageCount: 0,
            event: nil,
            message: message
        )
    }

    private func errorMessage(_ error: Error) -> String {
        if let ocrError = error as? AppleVisionOCRError {
            return ocrError.description
        }
        return error.localizedDescription
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
