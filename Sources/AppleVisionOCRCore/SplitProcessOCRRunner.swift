import CoreGraphics
import Darwin
import Foundation

public final class SplitProcessOCRRunner {
    public enum Output: Equatable {
        case searchablePDF(URL)
        case text(URL)
        case markdown(URL)
        case searchablePDFAndText(pdf: URL, text: URL)
    }

    public struct ProgressUpdate: Equatable {
        public let completedPages: Int
        public let totalPages: Int
    }

    private let executableURL: URL
    private let fileManager: FileManager
    private let layoutModelCheck: () throws -> Void

    public init(
        executableURL: URL,
        fileManager: FileManager = .default,
        layoutModelCheck: @escaping () throws -> Void = { _ = try LayoutModel.load() }
    ) {
        self.executableURL = executableURL
        self.fileManager = fileManager
        self.layoutModelCheck = layoutModelCheck
    }

    public func run(
        inputURL: URL,
        output: Output,
        workerCount: Int,
        languages: [String],
        recognitionLevel: OCRRecognitionLevel,
        renderScale: OCRRenderScale,
        usesLanguageCorrection: Bool = true,
        includePageBreaks: Bool = false,
        pageRange: ClosedRange<Int>? = nil,
        control: OCRJobControl = OCRJobControl(),
        onLog: ((String) -> Void)? = nil,
        onProgress: ((ProgressUpdate) -> Void)? = nil
    ) throws {
        guard let sourceDocument = CGPDFDocument(inputURL as CFURL) else {
            throw AppleVisionOCRError.pdfFailure("failed to open input PDF: \(inputURL.path)")
        }

        let pageCount = sourceDocument.numberOfPages
        guard pageCount > 0 else {
            throw AppleVisionOCRError.pdfFailure("input PDF has no pages: \(inputURL.path)")
        }

        let selectedPages = pageRange ?? 1...pageCount
        guard selectedPages.lowerBound >= 1, selectedPages.upperBound <= pageCount else {
            throw AppleVisionOCRError.invalidUsage(
                "page range \(selectedPages.lowerBound)-\(selectedPages.upperBound) exceeds page count \(pageCount)"
            )
        }
        let pageOffset = selectedPages.lowerBound - 1
        let effectiveWorkers = max(1, min(workerCount, selectedPages.count))
        // Entries under the shared $TMPDIR vanished mid-run on 2026-10-31 (deleter unknown), so chunks live in the user cache.
        let rootName = "apple-vision-ocr-split-\(UUID().uuidString)"
        var temporaryRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("apple-vision-ocr", isDirectory: true)
            .appendingPathComponent(rootName, isDirectory: true)
        if (try? fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)) == nil {
            // Sandboxed callers (e.g. Codex test runs) cannot write the cache folder.
            temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(rootName, isDirectory: true)
        }
        let outputDirectory = temporaryRoot.appendingPathComponent("out", isDirectory: true)

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        if case .searchablePDFAndText(let pdfOutputURL, let textOutputURL) = output {
            guard !fileManager.fileExists(atPath: pdfOutputURL.path) else {
                throw AppleVisionOCRError.outputAlreadyExists("output already exists: \(pdfOutputURL.path)")
            }
            guard !fileManager.fileExists(atPath: textOutputURL.path) else {
                throw AppleVisionOCRError.outputAlreadyExists("output already exists: \(textOutputURL.path)")
            }
        }

        if case .markdown(let outputURL) = output {
            guard !fileManager.fileExists(atPath: outputURL.path) else {
                throw AppleVisionOCRError.outputAlreadyExists("output already exists: \(outputURL.path)")
            }
            try layoutModelCheck()
        }

        let chunks = Self.planChunks(pageCount: selectedPages.count, workerCount: effectiveWorkers)
            .map { ($0.lowerBound + pageOffset)...($0.upperBound + pageOffset) }
            .enumerated().map {
            let baseURL = outputDirectory.appendingPathComponent("chunk-\($0.offset)")
            return Chunk(
                index: $0.offset,
                range: $0.element,
                outputURL: baseURL.appendingPathExtension(output.pathExtension),
                textOutputURL: output.textPathExtension.map { baseURL.appendingPathExtension($0) }
            )
        }

        try runChildProcesses(
            chunks,
            inputURL: inputURL,
            output: output,
            languages: languages,
            recognitionLevel: recognitionLevel,
            renderScale: renderScale,
            usesLanguageCorrection: usesLanguageCorrection,
            includePageBreaks: includePageBreaks,
            totalPages: selectedPages.count,
            control: control,
            onLog: onLog,
            onProgress: onProgress
        )
        if control.isCanceled {
            throw AppleVisionOCRError.pdfFailure("OCR job canceled")
        }

        switch output {
        case .searchablePDF(let outputURL):
            try Self.mergePDFs(chunks.map(\.outputURL), to: outputURL, fileManager: fileManager)
        case .markdown(let outputURL):
            try Self.writeCombinedMarkdown(chunks.map(\.outputURL), to: outputURL, fileManager: fileManager)
        case .text(let outputURL):
            try Self.writeCombinedText(chunks.map(\.outputURL), to: outputURL, fileManager: fileManager)
        case .searchablePDFAndText(let pdfOutputURL, let textOutputURL):
            try Self.mergePDFs(chunks.map(\.outputURL), to: pdfOutputURL, fileManager: fileManager)
            do {
                try Self.writeCombinedText(
                    chunks.map { $0.textOutputURL! },
                    to: textOutputURL,
                    fileManager: fileManager
                )
            } catch {
                try? fileManager.removeItem(at: pdfOutputURL)
                throw error
            }
        }
    }

    static func planChunks(pageCount: Int, workerCount: Int) -> [ClosedRange<Int>] {
        guard pageCount > 0 else {
            return []
        }

        let effectiveWorkers = max(1, min(workerCount, pageCount))
        let basePageCount = pageCount / effectiveWorkers
        let remainder = pageCount % effectiveWorkers
        var nextPageNumber = 1
        var chunks: [ClosedRange<Int>] = []

        for index in 0..<effectiveWorkers {
            let pagesInChunk = basePageCount + (index < remainder ? 1 : 0)
            let start = nextPageNumber
            let end = nextPageNumber + pagesInChunk - 1
            chunks.append(start...end)
            nextPageNumber = end + 1
        }

        return chunks
    }

    static func mergePDFs(
        _ pdfURLs: [URL],
        to outputURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !fileManager.fileExists(atPath: outputURL.path) else {
            throw AppleVisionOCRError.outputAlreadyExists("output already exists: \(outputURL.path)")
        }

        let directory = outputURL.deletingLastPathComponent()
        let temporaryURL = directory
            .appendingPathComponent(".\(outputURL.deletingPathExtension().lastPathComponent).\(UUID().uuidString)")
            .appendingPathExtension("tmp.pdf")

        do {
            try writeMergedPDF(pdfURLs, to: temporaryURL)
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func writeCombinedText(
        _ textURLs: [URL],
        to outputURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !fileManager.fileExists(atPath: outputURL.path) else {
            throw AppleVisionOCRError.outputAlreadyExists("output already exists: \(outputURL.path)")
        }

        var combined = ""
        for (index, textURL) in textURLs.enumerated() {
            if index > 0 {
                combined += "\n"
            }
            combined += try String(contentsOf: textURL, encoding: .utf8)
        }

        let directory = outputURL.deletingLastPathComponent()
        let temporaryURL = directory
            .appendingPathComponent(".\(outputURL.deletingPathExtension().lastPathComponent).\(UUID().uuidString)")
            .appendingPathExtension("tmp.txt")

        do {
            try combined.write(to: temporaryURL, atomically: false, encoding: .utf8)
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw AppleVisionOCRError.pdfFailure("failed to write text output: \(outputURL.path) (\(error.localizedDescription))")
        }
    }

    static func writeCombinedMarkdown(
        _ pageURLs: [URL],
        to outputURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !fileManager.fileExists(atPath: outputURL.path) else {
            throw AppleVisionOCRError.outputAlreadyExists("output already exists: \(outputURL.path)")
        }
        let pages = try pageURLs.flatMap { try JSONDecoder().decode([MarkdownPage].self, from: Data(contentsOf: $0)) }
        let markdown = MarkdownDocumentRenderer.render(pages: pages)
        try AtomicOutputWriter.write(Data(markdown.utf8), to: outputURL, fileManager: fileManager)
    }

    private struct Chunk {
        let index: Int
        let range: ClosedRange<Int>
        let outputURL: URL
        let textOutputURL: URL?
    }

    private struct Worker {
        let chunk: Chunk
        let process: Process
        let spawnTime: Date
        let attempt: Int
        let readers: DispatchGroup
    }

    private final class ProgressState {
        private let lock = NSLock()
        private let totalPages: Int
        private var completedPages = Set<Int>()
        private var stderrTails: [String: [String]] = [:]

        init(totalPages: Int) {
            self.totalPages = totalPages
        }

        func recordLine(_ line: String, workerKey: String, range: ClosedRange<Int>, isStderr: Bool) -> ProgressUpdate? {
            var update: ProgressUpdate?
            lock.lock()
            if isStderr {
                var tail = stderrTails[workerKey, default: []]
                tail.append(line)
                if tail.count > 20 {
                    tail.removeFirst(tail.count - 20)
                }
                stderrTails[workerKey] = tail
            }
            let prefix = "Completed page "
            if isStderr, line.hasPrefix(prefix) {
                let number = line.dropFirst(prefix.count)
                if !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }),
                   let page = Int(number), range.contains(page),
                   completedPages.count < totalPages, completedPages.insert(page).inserted {
                    update = ProgressUpdate(completedPages: completedPages.count, totalPages: totalPages)
                }
            }
            lock.unlock()
            return update
        }

        func stderrTail(for workerKey: String) -> String {
            lock.lock()
            defer { lock.unlock() }

            let tail = stderrTails[workerKey, default: []].joined(separator: "\n")
            if tail.isEmpty {
                return "no stderr output"
            }
            return tail
        }
    }

    private func runChildProcesses(
        _ chunks: [Chunk],
        inputURL: URL,
        output: Output,
        languages: [String],
        recognitionLevel: OCRRecognitionLevel,
        renderScale: OCRRenderScale,
        usesLanguageCorrection: Bool,
        includePageBreaks: Bool,
        totalPages: Int,
        control: OCRJobControl,
        onLog: ((String) -> Void)?,
        onProgress: ((ProgressUpdate) -> Void)?
    ) throws {
        let progressState = ProgressState(totalPages: totalPages)
        let readerGroup = DispatchGroup()
        let readerQueue = DispatchQueue(label: "apple-vision-ocr.split-process-reader", attributes: .concurrent)
        let progressQueue = DispatchQueue(label: "apple-vision-ocr.split-process-progress")
        var workers: [Worker] = []

        func startWorker(_ chunk: Chunk, attempt: Int) throws -> Worker {
            if control.isCanceled {
                throw AppleVisionOCRError.pdfFailure("OCR job canceled")
            }
            let readers = DispatchGroup()
            let workerKey = "\(chunk.index)-\(attempt)"
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let process = Process()
            // Not `taskpolicy -c utility`: in a macOS 27 test that clamp made split Markdown OCR 9-12x slower
            // (2026-11-04, see CURRENT_STATUS.md). nice only lowers threads without a QoS class, so it is not a network safeguard.
            // nice execs in place, so pause/cancel signals still reach the worker pid.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
            process.arguments = ["-n", "10", executableURL.path] + childArguments(
                for: chunk,
                inputURL: inputURL,
                output: output,
                languages: languages,
                recognitionLevel: recognitionLevel,
                renderScale: renderScale,
                usesLanguageCorrection: usesLanguageCorrection,
                includePageBreaks: includePageBreaks
            )
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = ProcessInfo.processInfo.environment.merging([
                "APPLE_VISION_OCR_PARENT_PID": String(ProcessInfo.processInfo.processIdentifier)
            ]) { _, childValue in childValue }

            let spawnTime = Date()
            try process.run()
            readerGroup.enter()
            for (pipe, isStderr) in [(stdoutPipe, false), (stderrPipe, true)] {
                Self.readLines(from: pipe, on: readerQueue, group: readers) { line in
                    progressQueue.sync {
                        if let update = progressState.recordLine(
                            line, workerKey: workerKey, range: chunk.range, isStderr: isStderr
                        ) {
                            onProgress?(update)
                        }
                    }
                }
            }
            readers.notify(queue: readerQueue) { readerGroup.leave() }
            return Worker(chunk: chunk, process: process, spawnTime: spawnTime,
                          attempt: attempt, readers: readers)
        }

        do {
            for chunk in chunks {
                workers.append(try startWorker(chunk, attempt: 1))
            }
            let failedWorker = try waitForWorkers(&workers, control: control) { worker in
                _ = worker.readers.wait(timeout: .now() + .seconds(2))
                if worker.process.terminationReason == .exit && worker.process.terminationStatus == 1 {
                    return nil
                }
                guard worker.attempt < 3 else { return nil }
                for url in [worker.chunk.outputURL, worker.chunk.textOutputURL].compactMap({ $0 }) {
                    if fileManager.fileExists(atPath: url.path) {
                        try fileManager.removeItem(at: url)
                    }
                }
                onLog?("split worker \(worker.chunk.index) (pages \(worker.chunk.range.lowerBound)-\(worker.chunk.range.upperBound)) failed (\(worker.process.terminationReason == .uncaughtSignal ? "signal" : "exit status") \(worker.process.terminationStatus)); retrying, attempt \(worker.attempt + 1)/3")
                return try startWorker(worker.chunk, attempt: worker.attempt + 1)
            }
            if let failedWorker {
                _ = readerGroup.wait(timeout: .now() + .seconds(2))
                throw AppleVisionOCRError.pdfFailure(
                    "split worker \(failedWorker.chunk.index) pages \(failedWorker.chunk.range.lowerBound)-\(failedWorker.chunk.range.upperBound) failed after \(failedWorker.attempt) attempt(s): \(progressState.stderrTail(for: "\(failedWorker.chunk.index)-\(failedWorker.attempt)"))"
                )
            }
            _ = readerGroup.wait(timeout: .now() + .seconds(5))
        } catch {
            terminateAndWait(for: workers)
            _ = readerGroup.wait(timeout: .now() + .seconds(2))
            throw error
        }
    }

    private func waitForWorkers(
        _ workers: inout [Worker],
        control: OCRJobControl,
        retry: (Worker) throws -> Worker?
    ) throws -> Worker? {
        var isSuspended = false
        var reportedWorkerIndices = Set<Int>()
        let timingEnabled = !(ProcessInfo.processInfo.environment["APPLE_VISION_OCR_SPLIT_TIMING"] ?? "").isEmpty

        while true {
            if control.isPaused && !isSuspended {
                for worker in workers where worker.process.isRunning {
                    kill(worker.process.processIdentifier, SIGSTOP)
                }
                isSuspended = true
            } else if !control.isPaused && isSuspended {
                for worker in workers where worker.process.isRunning {
                    kill(worker.process.processIdentifier, SIGCONT)
                }
                isSuspended = false
            }

            if control.isCanceled {
                if isSuspended {
                    for worker in workers where worker.process.isRunning {
                        kill(worker.process.processIdentifier, SIGCONT)
                    }
                    isSuspended = false
                }
                for worker in workers where worker.process.isRunning {
                    worker.process.terminate()
                }
                throw AppleVisionOCRError.pdfFailure("OCR job canceled")
            }

            if timingEnabled {
                for worker in workers where !worker.process.isRunning &&
                    reportedWorkerIndices.insert(worker.chunk.index).inserted {
                    let seconds = Date().timeIntervalSince(worker.spawnTime)
                    let message = String(
                        format: "[split] worker %d pages %d-%d done in %.2fs\n",
                        worker.chunk.index,
                        worker.chunk.range.lowerBound,
                        worker.chunk.range.upperBound,
                        seconds
                    )
                    FileHandle.standardError.write(Data(message.utf8))
                }
            }

            if let failedWorker = workers.first(where: {
                !$0.process.isRunning && ($0.process.terminationReason != .exit ||
                    $0.process.terminationStatus != ExitCode.success.rawValue)
            }) {
                if let replacement = try retry(failedWorker),
                   let index = workers.firstIndex(where: { $0.chunk.index == failedWorker.chunk.index }) {
                    if control.isPaused && !isSuspended {
                        for worker in workers where worker.process.isRunning {
                            kill(worker.process.processIdentifier, SIGSTOP)
                        }
                        isSuspended = true
                    }
                    if isSuspended {
                        kill(replacement.process.processIdentifier, SIGSTOP)
                    }
                    workers[index] = replacement
                    reportedWorkerIndices.remove(failedWorker.chunk.index)
                    continue
                }
                if isSuspended {
                    for worker in workers where worker.process.isRunning {
                        kill(worker.process.processIdentifier, SIGCONT)
                    }
                    isSuspended = false
                }
                terminateAndWait(for: workers)
                return failedWorker
            }

            if workers.allSatisfy({ !$0.process.isRunning && $0.process.terminationReason == .exit &&
                $0.process.terminationStatus == ExitCode.success.rawValue }) {
                return nil
            }

            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func terminateAndWait(for workers: [Worker]) {
        for worker in workers where worker.process.isRunning {
            worker.process.terminate()
        }

        let deadline = Date().addingTimeInterval(2)
        while workers.contains(where: { $0.process.isRunning }) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        for worker in workers where worker.process.isRunning {
            kill(worker.process.processIdentifier, SIGKILL)
        }
        for worker in workers where worker.process.isRunning {
            worker.process.waitUntilExit()
        }
    }

    private func childArguments(
        for chunk: Chunk,
        inputURL: URL,
        output: Output,
        languages: [String],
        recognitionLevel: OCRRecognitionLevel,
        renderScale: OCRRenderScale,
        usesLanguageCorrection: Bool,
        includePageBreaks: Bool
    ) -> [String] {
        var commonArguments = [
            "--lang", languages.joined(separator: ","),
            "--recognition-level", recognitionLevel.rawValue,
            "--render-scale", String(renderScale.value),
            "--page-range", "\(chunk.range.lowerBound)-\(chunk.range.upperBound)"
        ]
        if !usesLanguageCorrection {
            commonArguments.append("--no-language-correction")
        }
        if let pageParallelism = ProcessInfo.processInfo.environment[
            "APPLE_VISION_OCR_SPLIT_CHILD_PAGE_PARALLELISM"
        ] {
            commonArguments += ["--page-parallelism", pageParallelism]
        }

        switch output {
        case .searchablePDF:
            return [
                inputURL.path,
                "--output", chunk.outputURL.path
            ] + commonArguments
        case .markdown:
            return [inputURL.path, "--md-pages-output", chunk.outputURL.path] + commonArguments
        case .text:
            var arguments = [
                inputURL.path,
                "--txt-only",
                "--txt-output", chunk.outputURL.path
            ] + commonArguments
            if includePageBreaks {
                arguments.append("--page-breaks")
            }
            return arguments
        case .searchablePDFAndText:
            var arguments = [
                inputURL.path,
                "--output", chunk.outputURL.path,
                "--txt-output", chunk.textOutputURL!.path
            ] + commonArguments
            if includePageBreaks {
                arguments.append("--page-breaks")
            }
            return arguments
        }
    }

    private static func readLines(
        from pipe: Pipe,
        on queue: DispatchQueue,
        group: DispatchGroup,
        onLine: @escaping (String) -> Void
    ) {
        group.enter()
        queue.async {
            var buffer = Data()
            let handle = pipe.fileHandleForReading

            while true {
                let data = handle.availableData
                if data.isEmpty {
                    break
                }

                buffer.append(data)
                while let newlineIndex = buffer.firstIndex(of: 10) {
                    let lineData = buffer[..<newlineIndex]
                    buffer.removeSubrange(...newlineIndex)
                    if let line = String(data: Data(lineData), encoding: .utf8) {
                        onLine(line.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
                    }
                }
            }

            if !buffer.isEmpty,
               let line = String(data: buffer, encoding: .utf8) {
                onLine(line.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
            }

            try? handle.close()
            group.leave()
        }
    }

    private static func writeMergedPDF(_ pdfURLs: [URL], to outputURL: URL) throws {
        guard let context = CGContext(outputURL as CFURL, mediaBox: nil, nil) else {
            throw AppleVisionOCRError.pdfFailure("failed to create output PDF: \(outputURL.path)")
        }

        for pdfURL in pdfURLs {
            guard let document = CGPDFDocument(pdfURL as CFURL) else {
                throw AppleVisionOCRError.pdfFailure("failed to open split worker PDF: \(pdfURL.path)")
            }

            for pageIndex in 1...document.numberOfPages {
                guard let page = document.page(at: pageIndex) else {
                    throw AppleVisionOCRError.pdfFailure("split worker page missing: \(pdfURL.path) page \(pageIndex)")
                }

                var mediaBox = page.getBoxRect(.mediaBox)
                let pageInfo = withUnsafeBytes(of: &mediaBox) { bytes -> CFDictionary in
                    [kCGPDFContextMediaBox as String: Data(bytes)] as CFDictionary
                }
                context.beginPDFPage(pageInfo)
                context.drawPDFPage(page)
                context.endPDFPage()
            }
        }

        context.closePDF()
    }
}

private extension SplitProcessOCRRunner.Output {
    var pathExtension: String {
        switch self {
        case .searchablePDF:
            return "pdf"
        case .markdown:
            return "json"
        case .text:
            return "txt"
        case .searchablePDFAndText:
            return "pdf"
        }
    }

    var textPathExtension: String? {
        switch self {
        case .searchablePDF, .text, .markdown:
            return nil
        case .searchablePDFAndText:
            return "txt"
        }
    }
}
