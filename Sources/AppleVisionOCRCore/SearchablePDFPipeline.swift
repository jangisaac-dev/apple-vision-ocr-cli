import CoreGraphics
import Foundation

public final class SearchablePDFPipeline {
    public typealias ProgressHandler = (OCRProgressEvent) -> Void

    private let renderer: any PDFRendering
    private let recognizer: any TextRecognizing
    private let writer: PDFTextOverlayWriter
    private let textWriter: TextOutputWriter
    private let textPresenceDetector: PDFTextPresenceDetector

    public convenience init() {
        self.init(
            renderer: PDFRenderer(),
            recognizer: VisionTextRecognizer(),
            writer: PDFTextOverlayWriter(),
            textWriter: TextOutputWriter(),
            textPresenceDetector: PDFTextPresenceDetector()
        )
    }

    init(
        renderer: any PDFRendering = PDFRenderer(),
        recognizer: any TextRecognizing = VisionTextRecognizer(),
        writer: PDFTextOverlayWriter = PDFTextOverlayWriter(),
        textWriter: TextOutputWriter = TextOutputWriter(),
        textPresenceDetector: PDFTextPresenceDetector = PDFTextPresenceDetector()
    ) {
        self.renderer = renderer
        self.recognizer = recognizer
        self.writer = writer
        self.textWriter = textWriter
        self.textPresenceDetector = textPresenceDetector
    }

    public func run(options: CLIOptions, progress: @escaping (String) -> Void = { _ in }) throws {
        let jobOptions = try OCRJobOptions(
            inputURL: options.inputURL,
            pdfOutputURL: options.outputURL,
            textOutputURL: options.txtOutputURL,
            outputMode: options.outputMode,
            languages: options.languages,
            recognitionLevel: options.recognitionLevel,
            pageParallelism: options.pageParallelism,
            renderScale: options.renderScale
        )

        try run(job: jobOptions, control: OCRJobControl()) { event in
            progress(event.message)
        }
    }

    public func run(
        job options: OCRJobOptions,
        control: OCRJobControl = OCRJobControl(),
        pageLimiter externalPageLimiter: OCRParallelismLimiter? = nil,
        progress: @escaping ProgressHandler = { _ in }
    ) throws {
        progress(OCRProgressEvent(
            stage: .starting,
            currentFile: options.inputURL.lastPathComponent,
            completedPages: 0,
            totalPages: 0,
            message: "Starting OCR"
        ))

        guard let document = CGPDFDocument(options.inputURL as CFURL) else {
            throw AppleVisionOCRError.pdfFailure("failed to open input PDF: \(options.inputURL.path)")
        }
        guard document.numberOfPages > 0 else {
            throw AppleVisionOCRError.pdfFailure("input PDF has no pages: \(options.inputURL.path)")
        }

        let textPages = try pagesWithExistingTextIfNeeded(for: options)
        if !textPages.isEmpty {
            progress(OCRProgressEvent(
                stage: .starting,
                currentFile: options.inputURL.lastPathComponent,
                completedPages: 0,
                totalPages: document.numberOfPages,
                message: "Existing selectable text found; rasterizing affected pages"
            ))
        }

        let pageLimiter = externalPageLimiter ?? OCRParallelismLimiter(parallelism: options.pageParallelism)
        let pageResults = try recognizePages(
            pageCount: document.numberOfPages,
            options: options,
            textPages: textPages,
            control: control,
            pageLimiter: pageLimiter,
            progress: progress
        )

        if control.isCanceled {
            throw AppleVisionOCRError.pdfFailure("OCR job canceled")
        }

        progress(OCRProgressEvent(
            stage: .writingOutput,
            currentFile: options.inputURL.lastPathComponent,
            completedPages: document.numberOfPages,
            totalPages: document.numberOfPages,
            message: "Writing output"
        ))

        if options.outputMode.writesPDF, let pdfOutputURL = options.pdfOutputURL {
            try writePDFAtomically(sourceDocument: document, pages: pageResults, to: pdfOutputURL)
        }
        if options.outputMode.writesText, let textOutputURL = options.textOutputURL {
            try textWriter.write(
                pages: pageResults,
                includePageBreaks: options.outputMode.includesPageBreaks,
                to: textOutputURL
            )
        }

        progress(OCRProgressEvent(
            stage: .completed,
            currentFile: options.inputURL.lastPathComponent,
            completedPages: document.numberOfPages,
            totalPages: document.numberOfPages,
            message: "Completed OCR"
        ))
    }

    private func recognizePages(
        pageCount: Int,
        options: OCRJobOptions,
        textPages: Set<Int>,
        control: OCRJobControl,
        pageLimiter: OCRParallelismLimiter,
        progress: @escaping ProgressHandler
    ) throws -> [PDFPageOCRResult] {
        let resultLock = NSLock()
        let errorLock = NSLock()
        let pageLock = NSLock()
        let group = DispatchGroup()
        let workerQueue = DispatchQueue(
            label: "dev.oth.apple-vision-ocr.page-workers",
            qos: .userInitiated,
            attributes: .concurrent
        )
        var pageResults = Array<PDFPageOCRResult?>(repeating: nil, count: pageCount)
        var completedPages = 0
        var nextPageNumber = 1
        var firstError: Error?

        func nextPage() -> Int? {
            pageLock.withLock {
                guard nextPageNumber <= pageCount, !control.isCanceled else {
                    return nil
                }
                let pageNumber = nextPageNumber
                nextPageNumber += 1
                return pageNumber
            }
        }

        func recordError(_ error: Error) {
            errorLock.withLock {
                if firstError == nil {
                    firstError = error
                    control.cancel()
                    pageLimiter.wakeWaiters()
                }
            }
        }

        let workerCount = min(pageCount, OCRJobParallelism.maximumCount)
        for _ in 0..<workerCount {
            if control.isCanceled {
                break
            }

            group.enter()
            workerQueue.async { [renderer, recognizer] in
                defer { group.leave() }

                while !control.isCanceled {
                    guard pageLimiter.acquire(shouldCancel: { control.isCanceled }) else {
                        break
                    }

                    do {
                        defer { pageLimiter.release() }

                        guard let pageNumber = nextPage() else {
                            break
                        }

                        try control.waitIfPaused {
                            let completed = resultLock.withLock { completedPages }
                            progress(OCRProgressEvent(
                                stage: .paused,
                                currentFile: options.inputURL.lastPathComponent,
                                completedPages: completed,
                                totalPages: pageCount,
                                message: "Paused"
                            ))
                        }

                        guard let pageDocument = CGPDFDocument(options.inputURL as CFURL),
                              let page = pageDocument.page(at: pageNumber) else {
                            throw AppleVisionOCRError.pdfFailure("failed to read page \(pageNumber)")
                        }

                        let completedBeforePage = resultLock.withLock { completedPages }
                        progress(OCRProgressEvent(
                            stage: .renderingPage,
                            currentFile: options.inputURL.lastPathComponent,
                            completedPages: completedBeforePage,
                            totalPages: pageCount,
                            message: "Rendering page \(pageNumber)/\(pageCount)"
                        ))
                        let renderedPage = try renderer.render(page: page, scale: options.renderScale)

                        let completedBeforeOCR = resultLock.withLock { completedPages }
                        progress(OCRProgressEvent(
                            stage: .recognizingText,
                            currentFile: options.inputURL.lastPathComponent,
                            completedPages: completedBeforeOCR,
                            totalPages: pageCount,
                            message: "OCR page \(pageNumber)/\(pageCount)"
                        ))
                        let recognizedText = try recognizer.recognize(
                            image: renderedPage.image,
                            languages: options.languages,
                            recognitionLevel: options.recognitionLevel
                        )
                        let overlays = recognizedText.map {
                            PDFTextOverlay(
                                text: $0.text,
                                rect: GeometryMapper.map(normalizedBox: $0.boundingBox, in: renderedPage.geometry)
                            )
                        }

                        let result = PDFPageOCRResult(
                            pageNumber: pageNumber,
                            geometry: renderedPage.geometry,
                            overlays: overlays,
                            backgroundImage: textPages.contains(pageNumber) ? renderedPage.image : nil
                        )
                        let completedAfterPage = resultLock.withLock {
                            pageResults[pageNumber - 1] = result
                            completedPages += 1
                            return completedPages
                        }

                        progress(OCRProgressEvent(
                            stage: .recognizingText,
                            currentFile: options.inputURL.lastPathComponent,
                            completedPages: completedAfterPage,
                            totalPages: pageCount,
                            message: "Completed page \(pageNumber)/\(pageCount)"
                        ))
                    } catch {
                        recordError(error)
                        break
                    }
                }
            }
        }

        group.wait()

        if let firstError {
            throw firstError
        }
        if control.isCanceled {
            throw AppleVisionOCRError.pdfFailure("OCR job canceled")
        }

        return try pageResults.enumerated().map { index, result in
            guard let result else {
                throw AppleVisionOCRError.pdfFailure("missing OCR result for page \(index + 1)")
            }
            return result
        }
    }

    private func writePDFAtomically(sourceDocument: CGPDFDocument, pages: [PDFPageOCRResult], to outputURL: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: outputURL.path) else {
            throw AppleVisionOCRError.outputAlreadyExists("output already exists: \(outputURL.path)")
        }

        let directory = outputURL.deletingLastPathComponent()
        let temporaryURL = directory
            .appendingPathComponent(".\(outputURL.deletingPathExtension().lastPathComponent).\(UUID().uuidString)")
            .appendingPathExtension("tmp.pdf")

        do {
            try writer.write(sourceDocument: sourceDocument, pages: pages, to: temporaryURL)
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func pagesWithExistingTextIfNeeded(for options: OCRJobOptions) throws -> Set<Int> {
        guard options.outputMode.writesPDF else {
            return []
        }
        let report = try textPresenceDetector.inspect(options.inputURL)
        return Set(report.textPageNumbers)
    }
}
