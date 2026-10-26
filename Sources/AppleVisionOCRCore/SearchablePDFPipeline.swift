import CoreGraphics
import Foundation

private struct RenderedPageQueueItem {
    let pageNumber: Int
    let rendered: RenderedPDFPage
}

private final class BoundedRenderedPageQueue {
    private let condition = NSCondition()
    private let capacity: Int
    private var items: [RenderedPageQueueItem] = []
    private var finished = false
    private var canceled = false

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func enqueue(_ item: RenderedPageQueueItem, shouldCancel: () -> Bool) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        while items.count >= capacity && !finished && !canceled && !shouldCancel() {
            condition.wait()
        }

        guard !finished, !canceled, !shouldCancel() else {
            return false
        }

        items.append(item)
        condition.signal()
        return true
    }

    func dequeue(shouldCancel: () -> Bool) -> RenderedPageQueueItem? {
        condition.lock()
        defer { condition.unlock() }

        while items.isEmpty && !finished && !canceled && !shouldCancel() {
            condition.wait()
        }

        guard !canceled, !shouldCancel(), !items.isEmpty else {
            return nil
        }

        let item = items.removeFirst()
        condition.signal()
        return item
    }

    func finish() {
        condition.withLock {
            finished = true
            condition.broadcast()
        }
    }

    func cancel() {
        condition.withLock {
            canceled = true
            condition.broadcast()
        }
    }
}

public final class SearchablePDFPipeline {
    public typealias ProgressHandler = (OCRProgressEvent) -> Void

    private let renderer: any PDFRendering
    private let recognizer: any TextRecognizing
    private let writer: PDFTextOverlayWriter
    private let textWriter: TextOutputWriter
    private let textPresenceDetector: PDFTextPresenceDetector
    private let layoutLoader: () throws -> any LayoutAnalyzing
    private let tableRecognizer: any TableRecognizing

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
        textPresenceDetector: PDFTextPresenceDetector = PDFTextPresenceDetector(),
        layoutLoader: @escaping () throws -> any LayoutAnalyzing = { try LayoutModel.load() },
        tableRecognizer: any TableRecognizing = DocumentTableRecognizer()
    ) {
        self.renderer = renderer
        self.recognizer = recognizer
        self.writer = writer
        self.textWriter = textWriter
        self.textPresenceDetector = textPresenceDetector
        self.layoutLoader = layoutLoader
        self.tableRecognizer = tableRecognizer
    }

    public func run(options: CLIOptions, progress: @escaping (String) -> Void = { _ in }) throws {
        try run(options: options, control: OCRJobControl()) { event in
            progress(event.message)
        }
    }

    public func run(
        options: CLIOptions,
        control: OCRJobControl,
        progress: @escaping ProgressHandler = { _ in }
    ) throws {
        let jobOptions = try OCRJobOptions(
            inputURL: options.inputURL,
            pdfOutputURL: options.outputURL,
            textOutputURL: options.txtOutputURL,
            outputMode: options.outputMode,
            languages: options.languages,
            recognitionLevel: options.recognitionLevel,
            pageParallelism: options.pageParallelism,
            renderScale: options.renderScale,
            usesLanguageCorrection: options.usesLanguageCorrection,
            pageRange: options.pageRange,
            markdownOutputURL: options.mdOutputURL,
            markdownPagesOutputURL: options.mdPagesOutputURL
        )

        try run(job: jobOptions, control: control, progress: progress)
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
        let pageNumbers = try selectedPageNumbers(for: options, totalPageCount: document.numberOfPages)

        let layout = options.outputMode.writesMarkdown ? try layoutLoader() : nil
        let textPages = try pagesWithExistingTextIfNeeded(for: options, pageNumbers: pageNumbers)
        if !textPages.isEmpty {
            progress(OCRProgressEvent(
                stage: .starting,
                currentFile: options.inputURL.lastPathComponent,
                completedPages: 0,
                totalPages: pageNumbers.count,
                message: "Existing selectable text found; rasterizing affected pages"
            ))
        }

        let pageLimiter = externalPageLimiter ?? OCRParallelismLimiter(parallelism: options.pageParallelism)
        let results = try recognizePages(
            pageNumbers: pageNumbers,
            options: options,
            textPages: textPages,
            control: control,
            pageLimiter: pageLimiter,
            layout: layout,
            progress: progress
        )

        let pageResults = results.ocr
        if control.isCanceled {
            throw AppleVisionOCRError.pdfFailure("OCR job canceled")
        }

        progress(OCRProgressEvent(
            stage: .writingOutput,
            currentFile: options.inputURL.lastPathComponent,
            completedPages: pageNumbers.count,
            totalPages: pageNumbers.count,
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

        if options.outputMode.writesMarkdown {
            if let outputURL = options.markdownOutputURL {
                try AtomicOutputWriter.write(Data(MarkdownDocumentRenderer.render(pages: results.markdown).utf8), to: outputURL)
            }
            if let outputURL = options.markdownPagesOutputURL {
                try AtomicOutputWriter.write(JSONEncoder().encode(results.markdown), to: outputURL)
            }
        }

        progress(OCRProgressEvent(
            stage: .completed,
            currentFile: options.inputURL.lastPathComponent,
            completedPages: pageNumbers.count,
            totalPages: pageNumbers.count,
            message: "Completed OCR"
        ))
    }

    private func recognizePages(
        pageNumbers: [Int],
        options: OCRJobOptions,
        textPages: Set<Int>,
        control: OCRJobControl,
        pageLimiter: OCRParallelismLimiter,
        layout: (any LayoutAnalyzing)?,
        progress: @escaping ProgressHandler
    ) throws -> (ocr: [PDFPageOCRResult], markdown: [MarkdownPage]) {
        let resultLock = NSLock()
        let errorLock = NSLock()
        let pageLock = NSLock()
        var pageResults = Array<PDFPageOCRResult?>(repeating: nil, count: pageNumbers.count)
        var markdownPages = Array<MarkdownPage?>(repeating: nil, count: pageNumbers.count)
        var completedPages = 0
        var nextPageIndex = 0
        var firstError: Error?
        let pageResultIndexes = Dictionary(uniqueKeysWithValues: pageNumbers.enumerated().map { ($0.element, $0.offset) })
        let queueCapacity = positiveIntegerEnvironmentValue("APPLE_VISION_OCR_QUEUE_CAPACITY") ?? 32
        let renderedQueue = BoundedRenderedPageQueue(capacity: queueCapacity)

        func nextPage() -> Int? {
            pageLock.withLock {
                guard nextPageIndex < pageNumbers.count, !control.isCanceled else {
                    return nil
                }
                let pageNumber = pageNumbers[nextPageIndex]
                nextPageIndex += 1
                return pageNumber
            }
        }

        func recordError(_ error: Error) {
            errorLock.withLock {
                if firstError == nil {
                    firstError = error
                    control.cancel()
                    pageLimiter.wakeWaiters()
                    renderedQueue.cancel()
                }
            }
        }

        // Render and Vision work are split so rendering can stay ahead without
        // making consumers poll or outlive the producer side.
        let visionActiveLock = NSLock()
        var activeVisionCount = 0
        var maxConcurrentVision = 0
        let renderGroup = DispatchGroup()
        let visionGroup = DispatchGroup()

        let renderQueue = DispatchQueue(
            label: "dev.oth.apple-vision-ocr.render-producers",
            qos: .userInitiated,
            attributes: .concurrent
        )
        let visionQueue = DispatchQueue(
            label: "dev.oth.apple-vision-ocr.vision-consumers",
            qos: .userInitiated,
            attributes: .concurrent
        )

        let defaultRenderProducerCount = min(8, max(2, pageNumbers.count / 8))
        let renderProducerCount = min(
            pageNumbers.count,
            positiveIntegerEnvironmentValue("APPLE_VISION_OCR_RENDER_PRODUCERS") ?? defaultRenderProducerCount
        )
        let visionConsumerCount = min(OCRJobParallelism.maximumCount, pageNumbers.count)

        for _ in 0..<renderProducerCount {
            if control.isCanceled { break }
            renderGroup.enter()
            renderQueue.async { [renderer] in
                defer { renderGroup.leave() }

                let workerDocument = CGPDFDocument(options.inputURL as CFURL)

                while !control.isCanceled {
                    guard let pageNumber = nextPage() else { break }

                    guard let page = workerDocument?.page(at: pageNumber) else {
                        recordError(AppleVisionOCRError.pdfFailure("failed to read page \(pageNumber)"))
                        break
                    }

                    let completedBeforePage = resultLock.withLock { completedPages }
                    progress(OCRProgressEvent(
                        stage: .renderingPage,
                        currentFile: options.inputURL.lastPathComponent,
                        completedPages: completedBeforePage,
                        totalPages: pageNumbers.count,
                        message: "Rendering page \(pageNumber)"
                    ))

                    do {
                        let rendered = try renderer.render(page: page, scale: options.renderScale)
                        let enqueued = renderedQueue.enqueue(
                            RenderedPageQueueItem(pageNumber: pageNumber, rendered: rendered),
                            shouldCancel: { control.isCanceled }
                        )
                        if !enqueued {
                            break
                        }
                    } catch {
                        recordError(error)
                        break
                    }
                }
            }
        }

        for _ in 0..<visionConsumerCount {
            if control.isCanceled { break }
            visionGroup.enter()
            visionQueue.async { [recognizer, tableRecognizer] in
                defer { visionGroup.leave() }

                while !control.isCanceled {
                    guard let item = renderedQueue.dequeue(shouldCancel: { control.isCanceled }) else {
                        break
                    }

                    guard pageLimiter.acquire(shouldCancel: { control.isCanceled }) else {
                        break
                    }

                    visionActiveLock.withLock {
                        activeVisionCount += 1
                        maxConcurrentVision = max(maxConcurrentVision, activeVisionCount)
                    }

                    do {
                        defer {
                            visionActiveLock.withLock {
                                activeVisionCount -= 1
                            }
                            pageLimiter.release()
                        }

                        try control.waitIfPaused {
                            let completed = resultLock.withLock { completedPages }
                            progress(OCRProgressEvent(
                                stage: .paused,
                                currentFile: options.inputURL.lastPathComponent,
                                completedPages: completed,
                                totalPages: pageNumbers.count,
                                message: "Paused"
                            ))
                        }

                        let completedBeforeOCR = resultLock.withLock { completedPages }
                        progress(OCRProgressEvent(
                            stage: .recognizingText,
                            currentFile: options.inputURL.lastPathComponent,
                            completedPages: completedBeforeOCR,
                            totalPages: pageNumbers.count,
                            message: "OCR page \(item.pageNumber)"
                        ))

                        let recognizedText = try recognizer.recognize(
                            image: item.rendered.image,
                            languages: options.languages,
                            recognitionLevel: options.recognitionLevel,
                            usesLanguageCorrection: options.usesLanguageCorrection
                        )

                        var markdownPage: MarkdownPage?
                        if let layout {
                            try Self.checkCancellation(control)
                            let regions = try layout.regions(for: item.rendered.image)
                            let lines = Self.layoutLines(recognizedText)
                            markdownPage = try MarkdownPageAnalyzer.analyze(
                                pdfPage: item.pageNumber, regions: regions, lines: lines,
                                recognizeCrop: { rect in
                                    try Self.checkCancellation(control)
                                    guard let crop = Self.crop(item.rendered.image, rect: rect) else { return [] }
                                    let text = try recognizer.recognize(
                                        image: crop.image, languages: options.languages,
                                        recognitionLevel: options.recognitionLevel,
                                        usesLanguageCorrection: options.usesLanguageCorrection)
                                    return Self.layoutLines(text).map { line in
                                        LayoutLine(text: line.text, rect: CGRect(
                                            x: crop.rect.minX + line.rect.minX * crop.rect.width,
                                            y: crop.rect.minY + line.rect.minY * crop.rect.height,
                                            width: line.rect.width * crop.rect.width,
                                            height: line.rect.height * crop.rect.height))
                                    }
                                }, recognizeTable: { rect in
                                    try Self.checkCancellation(control)
                                    guard let crop = Self.crop(item.rendered.image, rect: rect) else { return nil }
                                    return try tableRecognizer.markdown(for: crop.image, languages: options.languages,
                                                                        usesLanguageCorrection: options.usesLanguageCorrection)
                                })
                            try Self.checkCancellation(control)
                        }

                        let overlays = recognizedText.map {
                            PDFTextOverlay(
                                text: $0.text,
                                rect: GeometryMapper.map(normalizedBox: $0.boundingBox, in: item.rendered.geometry)
                            )
                        }

                        let result = PDFPageOCRResult(
                            pageNumber: item.pageNumber,
                            geometry: item.rendered.geometry,
                            overlays: overlays,
                            backgroundImage: textPages.contains(item.pageNumber) ? item.rendered.image : nil
                        )

                        let completedAfter = resultLock.withLock {
                            let resultIndex = pageResultIndexes[item.pageNumber] ?? 0
                            pageResults[resultIndex] = result
                            markdownPages[resultIndex] = markdownPage
                            completedPages += 1
                            return completedPages
                        }

                        progress(OCRProgressEvent(
                            stage: .recognizingText,
                            currentFile: options.inputURL.lastPathComponent,
                            completedPages: completedAfter,
                            totalPages: pageNumbers.count,
                            message: "Completed page \(item.pageNumber)"
                        ))
                    } catch {
                        recordError(error)
                        break
                    }
                }
            }
        }

        renderGroup.wait()
        renderedQueue.finish()
        visionGroup.wait()

        if let firstError {
            throw firstError
        }
        if control.isCanceled {
            throw AppleVisionOCRError.pdfFailure("OCR job canceled")
        }

        if ProcessInfo.processInfo.environment["APPLE_VISION_OCR_DEBUG_PIPELINE"] == "1" {
            fputs("[VisionPipeline] Max concurrent Vision requests observed: \(maxConcurrentVision)\n", stderr)
        }

        let ocr = try pageResults.enumerated().map { index, result in
            guard let result else {
                throw AppleVisionOCRError.pdfFailure("missing OCR result for page \(pageNumbers[index])")
            }
            return result
        }
        return (ocr, markdownPages.compactMap { $0 })
    }

    private static func checkCancellation(_ control: OCRJobControl) throws {
        if control.isCanceled { throw AppleVisionOCRError.pdfFailure("OCR job canceled") }
    }

    static func layoutLines(_ text: [RecognizedTextBox]) -> [LayoutLine] {
        text.map { box in
            LayoutLine(text: box.text, rect: CGRect(x: box.boundingBox.minX, y: 1 - box.boundingBox.maxY,
                                                  width: box.boundingBox.width, height: box.boundingBox.height))
        }
    }

    static func crop(_ image: CGImage, rect: CGRect) -> (image: CGImage, rect: CGRect)? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let pixels = CGRect(x: floor(rect.minX * width), y: floor(rect.minY * height),
                            width: ceil(rect.maxX * width) - floor(rect.minX * width),
                            height: ceil(rect.maxY * height) - floor(rect.minY * height))
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !pixels.isNull, !pixels.isEmpty, let cropped = image.cropping(to: pixels) else { return nil }
        return (cropped, CGRect(x: pixels.minX / width, y: pixels.minY / height,
                               width: pixels.width / width, height: pixels.height / height))
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

    private func pagesWithExistingTextIfNeeded(for options: OCRJobOptions, pageNumbers: [Int]) throws -> Set<Int> {
        guard options.outputMode.writesPDF else {
            return []
        }
        let report = try textPresenceDetector.inspect(options.inputURL, pageNumbers: pageNumbers)
        return Set(report.textPageNumbers)
    }

    private func selectedPageNumbers(for options: OCRJobOptions, totalPageCount: Int) throws -> [Int] {
        guard let pageRange = options.pageRange else {
            return Array(1...totalPageCount)
        }
        guard pageRange.upperBound <= totalPageCount else {
            throw AppleVisionOCRError.invalidUsage(
                "page range \(pageRange.lowerBound)-\(pageRange.upperBound) exceeds page count \(totalPageCount)"
            )
        }
        return Array(pageRange)
    }
}

private extension NSCondition {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private func positiveIntegerEnvironmentValue(_ name: String) -> Int? {
    guard let rawValue = ProcessInfo.processInfo.environment[name],
          let value = Int(rawValue),
          value > 0 else {
        return nil
    }
    return value
}
