import Foundation

public struct CLIOptions {
    public let inputURL: URL
    public let outputURL: URL?
    public let txtOutputURL: URL?
    public let outputMode: OCRJobOutputMode
    public let includePageBreaks: Bool
    public let languages: [String]
    public let recognitionLevel: OCRRecognitionLevel
    public let pageParallelism: OCRJobParallelism
    public let renderScale: OCRRenderScale
    public let pageRange: ClosedRange<Int>?
    public let splitWorkers: Int?
    public let dryRun: Bool

    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        guard !arguments.isEmpty else {
            throw AppleVisionOCRError.invalidUsage("missing input PDF")
        }

        var inputURL: URL?
        var outputURL: URL?
        var wantsDefaultTextOutput = false
        var wantsTextOnlyOutput = false
        var txtOutputURL: URL?
        var includePageBreaks = false
        var languages = ["ko", "en"]
        var recognitionLevel = OCRRecognitionLevel.accurate
        var pageParallelism = OCRJobParallelism.default
        var renderScale = OCRRenderScale.quality
        var pageRange: ClosedRange<Int>?
        var splitWorkers: Int?
        var dryRun = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--output":
                let value = try valueAfterOption(argument, arguments: arguments, index: &index)
                outputURL = URL(fileURLWithPath: value)
            case "--txt":
                wantsDefaultTextOutput = true
            case "--txt-only":
                wantsTextOnlyOutput = true
            case "--txt-output":
                let value = try valueAfterOption(argument, arguments: arguments, index: &index)
                txtOutputURL = URL(fileURLWithPath: value)
            case "--page-breaks":
                includePageBreaks = true
            case "--lang":
                let value = try valueAfterOption(argument, arguments: arguments, index: &index)
                languages = try LanguageParser.parse(value)
            case "--recognition-level":
                let value = try valueAfterOption(argument, arguments: arguments, index: &index)
                recognitionLevel = try OCRRecognitionLevel.parse(value)
            case "--page-parallelism":
                let value = try valueAfterOption(argument, arguments: arguments, index: &index)
                pageParallelism = try parsePageParallelism(value)
            case "--render-scale":
                let value = try valueAfterOption(argument, arguments: arguments, index: &index)
                renderScale = try OCRRenderScale.parse(value)
            case "--page-range":
                let value = try valueAfterOption(argument, arguments: arguments, index: &index)
                pageRange = try parsePageRange(value)
            case "--split-workers":
                let value = try valueAfterOption(argument, arguments: arguments, index: &index)
                splitWorkers = try parseSplitWorkers(value)
            case "--dry-run":
                dryRun = true
            case "--help", "-h", "--version":
                throw AppleVisionOCRError.invalidUsage("\(argument) must be used without an input PDF")
            default:
                if argument.hasPrefix("--") {
                    throw AppleVisionOCRError.invalidUsage("unsupported argument: \(argument)")
                }
                guard inputURL == nil else {
                    throw AppleVisionOCRError.invalidUsage("only one input PDF is supported")
                }
                inputURL = URL(fileURLWithPath: argument)
            }

            index += 1
        }

        guard let inputURL else {
            throw AppleVisionOCRError.invalidUsage("missing input PDF")
        }

        guard !(wantsDefaultTextOutput && txtOutputURL != nil) else {
            throw AppleVisionOCRError.invalidUsage("use either --txt or --txt-output, not both")
        }
        guard !(wantsTextOnlyOutput && wantsDefaultTextOutput) else {
            throw AppleVisionOCRError.invalidUsage("use either --txt-only or --txt, not both")
        }
        guard !(wantsTextOnlyOutput && outputURL != nil) else {
            throw AppleVisionOCRError.invalidUsage("--txt-only cannot be used with --output")
        }
        guard !includePageBreaks || wantsDefaultTextOutput || wantsTextOnlyOutput || txtOutputURL != nil else {
            throw AppleVisionOCRError.invalidUsage("--page-breaks requires --txt, --txt-only, or --txt-output")
        }
        let resolvedOutputURL = try wantsTextOnlyOutput
            ? nil
            : outputURL ?? OutputPathResolver.defaultOutputURL(for: inputURL)
        let resolvedTextOutputURL = try wantsDefaultTextOutput || (wantsTextOnlyOutput && txtOutputURL == nil)
            ? OutputPathResolver.defaultTextOutputURL(for: inputURL)
            : txtOutputURL
        let outputMode = try OCRJobOutputMode(
            writesPDF: resolvedOutputURL != nil,
            writesText: resolvedTextOutputURL != nil,
            includesPageBreaks: includePageBreaks
        )
        if splitWorkers != nil {
            guard outputMode.writesText != outputMode.writesPDF else {
                throw AppleVisionOCRError.invalidUsage("--split-workers cannot be combined with simultaneous text and PDF output")
            }
        }
        if pageRange != nil {
            guard outputMode.writesText != outputMode.writesPDF else {
                throw AppleVisionOCRError.invalidUsage("--page-range requires text-only or PDF-only output")
            }
        }
        try validateRecognitionLanguages(languages, recognitionLevel: recognitionLevel)
        return CLIOptions(
            inputURL: inputURL,
            outputURL: resolvedOutputURL,
            txtOutputURL: resolvedTextOutputURL,
            outputMode: outputMode,
            includePageBreaks: includePageBreaks,
            languages: languages,
            recognitionLevel: recognitionLevel,
            pageParallelism: pageParallelism,
            renderScale: renderScale,
            pageRange: pageRange,
            splitWorkers: splitWorkers,
            dryRun: dryRun
        )
    }

    public func validateFileSystem(fileManager: FileManager = .default) throws {
        guard inputURL.pathExtension.lowercased() == "pdf" else {
            throw AppleVisionOCRError.inputFileProblem("input must be a PDF: \(inputURL.path)")
        }
        if let outputURL {
            guard outputURL.pathExtension.lowercased() == "pdf" else {
                throw AppleVisionOCRError.invalidUsage("output must be a PDF: \(outputURL.path)")
            }
        }
        if let txtOutputURL {
            guard txtOutputURL.pathExtension.lowercased() == "txt" else {
                throw AppleVisionOCRError.invalidUsage("text output must be a TXT file: \(txtOutputURL.path)")
            }
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw AppleVisionOCRError.inputFileProblem("input file does not exist: \(inputURL.path)")
        }
        guard fileManager.isReadableFile(atPath: inputURL.path) else {
            throw AppleVisionOCRError.inputFileProblem("input file is not readable: \(inputURL.path)")
        }

        let standardizedInput = inputURL.standardizedFileURL.path
        let standardizedOutput = outputURL?.standardizedFileURL.path
        if let outputURL, let standardizedOutput {
            guard standardizedInput != standardizedOutput else {
                throw AppleVisionOCRError.outputAlreadyExists("output path must differ from input path")
            }
            guard !fileManager.fileExists(atPath: outputURL.path) else {
                throw AppleVisionOCRError.outputAlreadyExists("output already exists: \(outputURL.path)")
            }
        }
        if let txtOutputURL {
            let standardizedTextOutput = txtOutputURL.standardizedFileURL.path
            guard standardizedInput != standardizedTextOutput else {
                throw AppleVisionOCRError.outputAlreadyExists("text output path must differ from input path")
            }
            guard standardizedOutput != standardizedTextOutput else {
                throw AppleVisionOCRError.outputAlreadyExists("text output path must differ from PDF output path")
            }
            guard !fileManager.fileExists(atPath: txtOutputURL.path) else {
                throw AppleVisionOCRError.outputAlreadyExists("text output already exists: \(txtOutputURL.path)")
            }
        }

        if let outputURL {
            let outputDirectory = outputURL.deletingLastPathComponent()
            guard fileManager.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw AppleVisionOCRError.inputFileProblem("output directory does not exist: \(outputDirectory.path)")
            }
        }
        if let txtOutputURL {
            let textOutputDirectory = txtOutputURL.deletingLastPathComponent()
            guard fileManager.fileExists(atPath: textOutputDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw AppleVisionOCRError.inputFileProblem("text output directory does not exist: \(textOutputDirectory.path)")
            }
        }
    }
}

private func valueAfterOption(_ option: String, arguments: [String], index: inout Int) throws -> String {
    let valueIndex = index + 1
    guard valueIndex < arguments.count else {
        throw AppleVisionOCRError.invalidUsage("missing value for \(option)")
    }

    let value = arguments[valueIndex]
    guard !value.hasPrefix("--") else {
        throw AppleVisionOCRError.invalidUsage("missing value for \(option)")
    }

    index = valueIndex
    return value
}

private func parsePageParallelism(_ rawValue: String) throws -> OCRJobParallelism {
    guard let count = Int(rawValue) else {
        throw AppleVisionOCRError.invalidUsage("page parallelism must be a number")
    }

    do {
        return try OCRJobParallelism(count: count)
    } catch OCRJobOptionError.invalidParallelism {
        throw AppleVisionOCRError.invalidUsage(
            "page parallelism must be between \(OCRJobParallelism.minimumCount) and \(OCRJobParallelism.maximumCount)"
        )
    }
}

private func parseSplitWorkers(_ rawValue: String) throws -> Int {
    guard let count = Int(rawValue), (2...16).contains(count) else {
        throw AppleVisionOCRError.invalidUsage("split workers must be between 2 and 16")
    }
    return count
}

private func parsePageRange(_ rawValue: String) throws -> ClosedRange<Int> {
    let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2,
          let start = Int(parts[0]),
          let end = Int(parts[1]),
          start > 0,
          end >= start else {
        throw AppleVisionOCRError.invalidUsage("page range must be START-END")
    }
    return start...end
}

private func validateRecognitionLanguages(
    _ languages: [String],
    recognitionLevel: OCRRecognitionLevel
) throws {
    let unsupportedLanguages: [String]
    do {
        unsupportedLanguages = try VisionLanguageResolver.unsupportedLanguages(
            languages,
            recognitionLevel: recognitionLevel
        )
    } catch {
        throw AppleVisionOCRError.visionFailure("failed to inspect Vision recognition language support")
    }

    guard unsupportedLanguages.isEmpty else {
        throw AppleVisionOCRError.invalidUsage(
            "\(recognitionLevel.rawValue) recognition does not support: \(unsupportedLanguages.joined(separator: ", "))"
        )
    }
}
