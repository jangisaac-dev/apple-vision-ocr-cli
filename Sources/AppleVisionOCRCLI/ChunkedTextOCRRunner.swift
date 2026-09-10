import Foundation
import AppleVisionOCRCore

final class ChunkedTextOCRRunner {
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
              let textOutputURL = options.txtOutputURL else {
            throw AppleVisionOCRError.invalidUsage("--split-workers requires --txt-only text output")
        }

        stderr("Running split text OCR with \(splitWorkers) worker processes")
        try SplitProcessOCRRunner(executableURL: executableURL, fileManager: fileManager).run(
            inputURL: options.inputURL,
            output: .text(textOutputURL),
            workerCount: splitWorkers,
            languages: options.languages,
            recognitionLevel: options.recognitionLevel,
            renderScale: options.renderScale,
            usesLanguageCorrection: options.usesLanguageCorrection,
            includePageBreaks: options.includePageBreaks
        )
    }
}
