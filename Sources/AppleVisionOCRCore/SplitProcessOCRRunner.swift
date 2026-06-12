import CoreGraphics
import Darwin
import Foundation

public final class SplitProcessOCRRunner {
    public enum Output: Equatable {
        case searchablePDF(URL)
        case text(URL)
    }

    public struct ProgressUpdate: Equatable {
        public let completedPages: Int
        public let totalPages: Int
    }

    private let executableURL: URL
    private let fileManager: FileManager

    public init(executableURL: URL, fileManager: FileManager = .default) {
        self.executableURL = executableURL
        self.fileManager = fileManager
    }

    public func run(
        inputURL: URL,
        output: Output,
        workerCount: Int,
        languages: [String],
        recognitionLevel: OCRRecognitionLevel,
        renderScale: OCRRenderScale,
        control: OCRJobControl = OCRJobControl(),
        onProgress: ((ProgressUpdate) -> Void)? = nil
    ) throws {
        guard let sourceDocument = CGPDFDocument(inputURL as CFURL) else {
            throw AppleVisionOCRError.pdfFailure("failed to open input PDF: \(inputURL.path)")
        }

        let pageCount = sourceDocument.numberOfPages
        guard pageCount > 0 else {
            throw AppleVisionOCRError.pdfFailure("input PDF has no pages: \(inputURL.path)")
        }

        let effectiveWorkers = max(1, min(workerCount, pageCount))
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("apple-vision-ocr-split-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = temporaryRoot.appendingPathComponent("out", isDirectory: true)

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let chunks = Self.planChunks(pageCount: pageCount, workerCount: effectiveWorkers).enumerated().map {
            Chunk(
                index: $0.offset,
                range: $0.element,
                outputURL: outputDirectory.appendingPathComponent("chunk-\($0.offset).\(output.pathExtension)")
            )
        }

        try runChildProcesses(
            chunks,
            inputURL: inputURL,
            output: output,
            languages: languages,
            recognitionLevel: recognitionLevel,
            renderScale: renderScale,
            totalPages: pageCount,
            control: control,
            onProgress: onProgress
        )
        if control.isCanceled {
            throw AppleVisionOCRError.pdfFailure("OCR job canceled")
        }

        switch output {
        case .searchablePDF(let outputURL):
            try Self.mergePDFs(chunks.map(\.outputURL), to: outputURL, fileManager: fileManager)
        case .text(let outputURL):
            try Self.writeCombinedText(chunks.map(\.outputURL), to: outputURL)
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

    static func writeCombinedText(_ textURLs: [URL], to outputURL: URL) throws {
        var combined = ""
        for (index, textURL) in textURLs.enumerated() {
            if index > 0 {
                combined += "\n"
            }
            combined += try String(contentsOf: textURL, encoding: .utf8)
        }

        do {
            try combined.write(to: outputURL, atomically: true, encoding: .utf8)
        } catch {
            throw AppleVisionOCRError.pdfFailure("failed to write text output: \(outputURL.path)")
        }
    }

    private struct Chunk {
        let index: Int
        let range: ClosedRange<Int>
        let outputURL: URL
    }

    private struct Worker {
        let chunk: Chunk
        let process: Process
    }

    private final class ProgressState {
        private let lock = NSLock()
        private let totalPages: Int
        private var completedPages = 0
        private var stderrTails: [Int: [String]] = [:]

        init(totalPages: Int) {
            self.totalPages = totalPages
        }

        func recordLine(_ line: String, workerIndex: Int, isStderr: Bool) -> ProgressUpdate? {
            var update: ProgressUpdate?
            lock.lock()
            if isStderr {
                var tail = stderrTails[workerIndex, default: []]
                tail.append(line)
                if tail.count > 20 {
                    tail.removeFirst(tail.count - 20)
                }
                stderrTails[workerIndex] = tail
            }
            if line.contains("Completed page") {
                completedPages += 1
                update = ProgressUpdate(completedPages: completedPages, totalPages: totalPages)
            }
            lock.unlock()
            return update
        }

        func stderrTail(for workerIndex: Int) -> String {
            lock.lock()
            defer { lock.unlock() }

            let tail = stderrTails[workerIndex, default: []].joined(separator: "\n")
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
        totalPages: Int,
        control: OCRJobControl,
        onProgress: ((ProgressUpdate) -> Void)?
    ) throws {
        let progressState = ProgressState(totalPages: totalPages)
        let readerGroup = DispatchGroup()
        let readerQueue = DispatchQueue(label: "apple-vision-ocr.split-process-reader", attributes: .concurrent)
        var workers: [Worker] = []

        do {
            for chunk in chunks {
                if control.isCanceled {
                    throw AppleVisionOCRError.pdfFailure("OCR job canceled")
                }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let process = Process()
                process.executableURL = executableURL
                process.arguments = childArguments(
                    for: chunk,
                    inputURL: inputURL,
                    output: output,
                    languages: languages,
                    recognitionLevel: recognitionLevel,
                    renderScale: renderScale
                )
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                try process.run()
                workers.append(Worker(chunk: chunk, process: process))

                Self.readLines(from: stdoutPipe, on: readerQueue, group: readerGroup) { line in
                    if let update = progressState.recordLine(line, workerIndex: chunk.index, isStderr: false) {
                        onProgress?(update)
                    }
                }
                Self.readLines(from: stderrPipe, on: readerQueue, group: readerGroup) { line in
                    if let update = progressState.recordLine(line, workerIndex: chunk.index, isStderr: true) {
                        onProgress?(update)
                    }
                }
            }

            let failedWorker = try waitForWorkers(workers, control: control)
            readerGroup.wait()
            if let failedWorker {
                throw AppleVisionOCRError.pdfFailure(
                    "split worker \(failedWorker.chunk.index) failed: \(progressState.stderrTail(for: failedWorker.chunk.index))"
                )
            }
        } catch {
            for worker in workers where worker.process.isRunning {
                worker.process.terminate()
            }
            for worker in workers where worker.process.isRunning {
                worker.process.waitUntilExit()
            }
            readerGroup.wait()
            throw error
        }
    }

    private func waitForWorkers(
        _ workers: [Worker],
        control: OCRJobControl
    ) throws -> Worker? {
        var isSuspended = false

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

            if let failedWorker = workers.first(where: {
                !$0.process.isRunning && $0.process.terminationStatus != ExitCode.success.rawValue
            }) {
                if isSuspended {
                    for worker in workers where worker.process.isRunning {
                        kill(worker.process.processIdentifier, SIGCONT)
                    }
                    isSuspended = false
                }
                for worker in workers where worker.process.isRunning {
                    worker.process.terminate()
                }
                for worker in workers where worker.process.isRunning {
                    worker.process.waitUntilExit()
                }
                return failedWorker
            }

            if workers.allSatisfy({ !$0.process.isRunning }) {
                return nil
            }

            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func childArguments(
        for chunk: Chunk,
        inputURL: URL,
        output: Output,
        languages: [String],
        recognitionLevel: OCRRecognitionLevel,
        renderScale: OCRRenderScale
    ) -> [String] {
        let commonArguments = [
            "--lang", languages.joined(separator: ","),
            "--recognition-level", recognitionLevel.rawValue,
            "--render-scale", String(renderScale.value),
            "--page-range", "\(chunk.range.lowerBound)-\(chunk.range.upperBound)"
        ]

        switch output {
        case .searchablePDF:
            return [
                inputURL.path,
                "--output", chunk.outputURL.path
            ] + commonArguments
        case .text:
            return [
                inputURL.path,
                "--txt-only",
                "--txt-output", chunk.outputURL.path
            ] + commonArguments
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
        case .text:
            return "txt"
        }
    }
}
