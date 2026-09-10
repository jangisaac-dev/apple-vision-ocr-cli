import Foundation
import AppleVisionOCRCore

public final class CommandRunner {
    public static let version = "1.0.0"

    private let stdout: (String) -> Void
    private let stderr: (String) -> Void
    private let pipeline: SearchablePDFPipeline
    private let executableURL: URL

    public init(
        stdout: @escaping (String) -> Void = { print($0) },
        stderr: @escaping (String) -> Void = { message in
            FileHandle.standardError.write(Data((message + "\n").utf8))
        },
        pipeline: SearchablePDFPipeline = SearchablePDFPipeline(),
        executableURL: URL? = nil
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.pipeline = pipeline
        self.executableURL = executableURL ?? Self.defaultExecutableURL()
    }

    public func run(arguments: [String]) -> ExitCode {
        do {
            switch try CLICommand.parse(arguments) {
            case .help:
                stdout(Self.helpText)
                return .success
            case .version:
                stdout("apple-vision-ocr \(Self.version)")
                return .success
            case .run(let options):
                try options.validateFileSystem()

                if options.dryRun {
                    if let outputURL = options.outputURL {
                        stdout(outputURL.path)
                    }
                    if let txtOutputURL = options.txtOutputURL {
                        stdout(txtOutputURL.path)
                    }
                    return .success
                }

                if options.splitWorkers != nil {
                    if let outputURL = options.outputURL,
                       let textOutputURL = options.txtOutputURL,
                       let splitWorkers = options.splitWorkers {
                        stderr("Running split PDF and text OCR with \(splitWorkers) worker processes")
                        try SplitProcessOCRRunner(executableURL: executableURL).run(
                            inputURL: options.inputURL,
                            output: .searchablePDFAndText(pdf: outputURL, text: textOutputURL),
                            workerCount: splitWorkers,
                            languages: options.languages,
                            recognitionLevel: options.recognitionLevel,
                            renderScale: options.renderScale,
                            usesLanguageCorrection: options.usesLanguageCorrection,
                            includePageBreaks: options.includePageBreaks
                        )
                    } else if options.outputURL != nil {
                        try ChunkedPDFOCRRunner(
                            options: options,
                            executableURL: executableURL,
                            stderr: stderr
                        ).run()
                    } else {
                        try ChunkedTextOCRRunner(
                            options: options,
                            executableURL: executableURL,
                            stderr: stderr
                        ).run()
                    }
                } else {
                    try pipeline.run(options: options) { [stderr] message in
                        stderr(message)
                    }
                }
                if let outputURL = options.outputURL {
                    stdout(outputURL.path)
                }
                if let txtOutputURL = options.txtOutputURL {
                    stdout(txtOutputURL.path)
                }
                return .success
            }
        } catch let error as AppleVisionOCRError {
            stderr("error: \(error.description)")
            return error.exitCode
        } catch {
            stderr("error: \(error.localizedDescription)")
            return .pdfFailure
        }
    }

    private static let helpText = """
    Usage:
      apple-vision-ocr input.pdf [--output output.pdf] [--txt|--txt-output output.txt|--txt-only] [--page-breaks] [--lang ko,en] [--recognition-level accurate|fast] [--page-parallelism 1-16] [--render-scale 1.25|1.5|2.0] [--no-language-correction] [--page-range START-END] [--split-workers 2-16] [--dry-run]
      apple-vision-ocr --help
      apple-vision-ocr --version

    Options:
      --output PATH              Write searchable PDF to PATH. Defaults to input_ocr.pdf.
      --txt                      Also write OCR text to input.txt.
      --txt-output PATH          Also write OCR text to PATH.
      --txt-only                 Write only OCR text to input.txt, or to --txt-output when provided.
      --page-breaks              Include ===== Page N ===== markers in text output.
      --lang LIST                Comma-separated Vision language list. Defaults to ko,en.
      --recognition-level VALUE  accurate or fast. Defaults to accurate. Fast supports a limited language set.
      --page-parallelism N       OCR up to N pages at once. Defaults to 8.
      --render-scale N           PDF render scale: 2.0 quality, 1.5 balanced Korean speed, 1.25 compact.
      --no-language-correction   Disable Vision language correction for faster OCR.
      --page-range START-END     OCR only a 1-based page range.
      --split-workers N          Split OCR across N child processes.
      --dry-run                  Validate arguments and print the output path without writing.
      --help                     Show this help text.
      --version                  Show the version.
    """

    private static func defaultExecutableURL() -> URL {
        let executable = CommandLine.arguments.first ?? "apple-vision-ocr"
        if executable.contains("/") {
            return URL(fileURLWithPath: executable).standardizedFileURL
        }

        let fileManager = FileManager.default
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(executable)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate.standardizedFileURL
            }
        }

        return URL(fileURLWithPath: executable)
    }
}

enum CLICommand {
    case help
    case version
    case run(CLIOptions)

    static func parse(_ arguments: [String]) throws -> CLICommand {
        if arguments == ["--help"] || arguments == ["-h"] {
            return .help
        }
        if arguments == ["--version"] {
            return .version
        }
        return .run(try CLIOptions.parse(arguments))
    }
}
