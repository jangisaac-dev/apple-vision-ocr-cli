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

        stderr("Running split PDF OCR with \(splitWorkers) worker processes")
        try SplitProcessOCRRunner(executableURL: executableURL, fileManager: fileManager).run(
            inputURL: options.inputURL,
            output: .searchablePDF(outputURL),
            workerCount: splitWorkers,
            languages: options.languages,
            recognitionLevel: options.recognitionLevel,
            renderScale: options.renderScale,
            usesLanguageCorrection: options.usesLanguageCorrection
        )
    }
}
