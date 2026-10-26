import Foundation

public enum OCRJobOptionError: Error, Equatable {
    case missingOutput
    case markdownIsExclusive
    case missingMarkdownOutputURL
    case pageBreaksRequireText
    case missingPDFOutputURL
    case missingTextOutputURL
    case invalidParallelism
    case unsupportedRecognitionLanguage
}

public struct OCRJobOutputMode: Equatable {
    public let writesPDF: Bool
    public let writesText: Bool
    public let includesPageBreaks: Bool
    public let writesMarkdown: Bool

    public init(writesPDF: Bool, writesText: Bool, includesPageBreaks: Bool, writesMarkdown: Bool = false) throws {
        guard !writesMarkdown || (!writesPDF && !writesText && !includesPageBreaks) else {
            throw OCRJobOptionError.markdownIsExclusive
        }
        guard writesPDF || writesText || writesMarkdown else {
            throw OCRJobOptionError.missingOutput
        }
        guard writesText || !includesPageBreaks else {
            throw OCRJobOptionError.pageBreaksRequireText
        }

        self.writesPDF = writesPDF
        self.writesText = writesText
        self.includesPageBreaks = includesPageBreaks
        self.writesMarkdown = writesMarkdown
    }

    public static let markdown = try! OCRJobOutputMode(
        writesPDF: false,
        writesText: false,
        includesPageBreaks: false,
        writesMarkdown: true
    )

    public static let searchablePDF = try! OCRJobOutputMode(
        writesPDF: true,
        writesText: false,
        includesPageBreaks: false
    )

    public static let plainText = try! OCRJobOutputMode(
        writesPDF: false,
        writesText: true,
        includesPageBreaks: false
    )

    public static let textAndSearchablePDF = try! OCRJobOutputMode(
        writesPDF: true,
        writesText: true,
        includesPageBreaks: false
    )

    public static let pageDividedText = try! OCRJobOutputMode(
        writesPDF: false,
        writesText: true,
        includesPageBreaks: true
    )
}

public struct OCRJobOutputSelection: Equatable {
    public let writesText: Bool
    public let writesPDF: Bool
    public let includesPageBreaks: Bool
    public let writesMarkdown: Bool
    public let outputMode: OCRJobOutputMode

    public init(writesText: Bool, writesPDF: Bool, includesPageBreaks: Bool, writesMarkdown: Bool = false) throws {
        let outputMode = try OCRJobOutputMode(
            writesPDF: writesPDF,
            writesText: writesText,
            includesPageBreaks: includesPageBreaks,
            writesMarkdown: writesMarkdown
        )
        self.writesText = writesText
        self.writesPDF = writesPDF
        self.includesPageBreaks = includesPageBreaks
        self.writesMarkdown = writesMarkdown
        self.outputMode = outputMode
    }
}

public struct OCRJobParallelism: Equatable {
    public static let minimumCount = 1
    public static let maximumCount = 16
    public static let serial = try! OCRJobParallelism(count: minimumCount)
    public static let `default` = try! OCRJobParallelism(count: 8)

    public static func recommendedWorkerCount(
        activeProcessorCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> Int {
        min(maximumCount, max(2, activeProcessorCount * 2 / 3 - 2))
    }

    public let count: Int

    public init(count: Int) throws {
        guard count >= Self.minimumCount, count <= Self.maximumCount else {
            throw OCRJobOptionError.invalidParallelism
        }
        self.count = count
    }
}

public struct OCRJobOptions: Equatable {
    public let inputURL: URL
    public let pdfOutputURL: URL?
    public let textOutputURL: URL?
    public let outputMode: OCRJobOutputMode
    public let languages: [String]
    public let recognitionLevel: OCRRecognitionLevel
    public let pageParallelism: OCRJobParallelism
    public let renderScale: OCRRenderScale
    public let usesLanguageCorrection: Bool
    public let pageRange: ClosedRange<Int>?
    public let markdownOutputURL: URL?
    public let markdownPagesOutputURL: URL?

    public init(
        inputURL: URL,
        pdfOutputURL: URL?,
        textOutputURL: URL?,
        outputMode: OCRJobOutputMode,
        languages: [String] = ["ko", "en"],
        recognitionLevel: OCRRecognitionLevel = .accurate,
        pageParallelism: OCRJobParallelism = .default,
        renderScale: OCRRenderScale = .quality,
        usesLanguageCorrection: Bool = true,
        pageRange: ClosedRange<Int>? = nil,
        markdownOutputURL: URL? = nil,
        markdownPagesOutputURL: URL? = nil
    ) throws {
        if outputMode.writesPDF, pdfOutputURL == nil {
            throw OCRJobOptionError.missingPDFOutputURL
        }
        if outputMode.writesText, textOutputURL == nil {
            throw OCRJobOptionError.missingTextOutputURL
        }
        if outputMode.writesMarkdown, (markdownOutputURL == nil) == (markdownPagesOutputURL == nil) {
            throw OCRJobOptionError.missingMarkdownOutputURL
        }
        if let unsupportedLanguages = try? VisionLanguageResolver.unsupportedLanguages(
            languages,
            recognitionLevel: recognitionLevel
        ), !unsupportedLanguages.isEmpty {
            throw OCRJobOptionError.unsupportedRecognitionLanguage
        }

        self.inputURL = inputURL
        self.pdfOutputURL = pdfOutputURL
        self.textOutputURL = textOutputURL
        self.outputMode = outputMode
        self.languages = languages
        self.recognitionLevel = recognitionLevel
        self.pageParallelism = pageParallelism
        self.renderScale = renderScale
        self.usesLanguageCorrection = usesLanguageCorrection
        self.pageRange = pageRange
        self.markdownOutputURL = markdownOutputURL
        self.markdownPagesOutputURL = markdownPagesOutputURL
    }
}
