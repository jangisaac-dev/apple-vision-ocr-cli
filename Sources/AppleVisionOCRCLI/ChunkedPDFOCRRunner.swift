import CoreGraphics
import Foundation
import AppleVisionOCRCore

final class ChunkedPDFOCRRunner {
    private let options: CLIOptions
    private let executableURL: URL
    private let stderr: (String) -> Void
    private let fileManager: FileManager

    init(
        options: CLIOptions,
        executableURL: URL,
        stderr: @escaping (String) -> Void,
        fileManager: FileManager = .default
    ) {
        self.options = options
        self.executableURL = executableURL
        self.stderr = stderr
        self.fileManager = fileManager
    }

    func run() throws {
        guard let splitWorkers = options.splitWorkers,
              let outputURL = options.outputURL else {
            throw AppleVisionOCRError.invalidUsage("--split-workers requires PDF output")
        }

        guard let sourceDocument = CGPDFDocument(options.inputURL as CFURL) else {
            throw AppleVisionOCRError.pdfFailure("failed to open input PDF: \(options.inputURL.path)")
        }

        let pageCount = sourceDocument.numberOfPages
        guard pageCount > 0 else {
            throw AppleVisionOCRError.pdfFailure("input PDF has no pages: \(options.inputURL.path)")
        }

        let workerCount = min(splitWorkers, pageCount)
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("apple-vision-ocr-split-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = temporaryRoot.appendingPathComponent("out", isDirectory: true)

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let chunks = makeChunks(pageCount: pageCount, workerCount: workerCount, outputDirectory: outputDirectory)

        stderr("Running split PDF OCR with \(workerCount) worker processes")
        try runChildProcesses(chunks)
        try mergePDFs(chunks.map(\.pdfURL), to: outputURL)
    }

    private struct Chunk {
        let index: Int
        let range: ClosedRange<Int>
        let pdfURL: URL
        let logURL: URL
    }

    private func makeChunks(pageCount: Int, workerCount: Int, outputDirectory: URL) -> [Chunk] {
        let basePageCount = pageCount / workerCount
        let remainder = pageCount % workerCount
        var nextPageNumber = 1
        var chunks: [Chunk] = []

        for index in 0..<workerCount {
            let pagesInChunk = basePageCount + (index < remainder ? 1 : 0)
            let start = nextPageNumber
            let end = nextPageNumber + pagesInChunk - 1
            chunks.append(Chunk(
                index: index,
                range: start...end,
                pdfURL: outputDirectory.appendingPathComponent("chunk-\(index).pdf"),
                logURL: outputDirectory.appendingPathComponent("chunk-\(index).log")
            ))
            nextPageNumber = end + 1
        }

        return chunks
    }

    private func runChildProcesses(_ chunks: [Chunk]) throws {
        var running: [(chunk: Chunk, process: Process, logHandle: FileHandle)] = []

        do {
            for chunk in chunks {
                let logHandle = try FileHandle(forWritingTo: createFile(at: chunk.logURL))
                let process = Process()
                process.executableURL = executableURL
                process.arguments = childArguments(for: chunk)
                process.standardOutput = logHandle
                process.standardError = logHandle
                try process.run()
                running.append((chunk, process, logHandle))
            }

            for item in running {
                item.process.waitUntilExit()
                try item.logHandle.close()
                guard item.process.terminationStatus == ExitCode.success.rawValue else {
                    throw AppleVisionOCRError.pdfFailure(
                        "split worker \(item.chunk.index) failed; see \(item.chunk.logURL.path)"
                    )
                }
            }
        } catch {
            for item in running where item.process.isRunning {
                item.process.terminate()
            }
            throw error
        }
    }

    private func childArguments(for chunk: Chunk) -> [String] {
        [
            options.inputURL.path,
            "--output", chunk.pdfURL.path,
            "--lang", options.languages.joined(separator: ","),
            "--recognition-level", options.recognitionLevel.rawValue,
            "--page-parallelism", "\(options.pageParallelism.count)",
            "--render-scale", "\(options.renderScale.value)",
            "--page-range", "\(chunk.range.lowerBound)-\(chunk.range.upperBound)"
        ]
    }

    private func mergePDFs(_ pdfURLs: [URL], to outputURL: URL) throws {
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

    private func writeMergedPDF(_ pdfURLs: [URL], to outputURL: URL) throws {
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

    private func createFile(at url: URL) throws -> URL {
        fileManager.createFile(atPath: url.path, contents: nil)
        return url
    }
}
