import Foundation
import AppleVisionOCRCore

public final class CommandRunner {
    public static let version = "1.0.0"

    private let stdout: (String) -> Void
    private let stderr: (String) -> Void
    private let pipeline: SearchablePDFPipeline

    public init(
        stdout: @escaping (String) -> Void = { print($0) },
        stderr: @escaping (String) -> Void = { message in
            FileHandle.standardError.write(Data((message + "\n").utf8))
        },
        pipeline: SearchablePDFPipeline = SearchablePDFPipeline()
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.pipeline = pipeline
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

                try pipeline.run(options: options) { [stderr] message in
                    stderr(message)
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
      apple-vision-ocr input.pdf [--output output.pdf] [--txt|--txt-output output.txt|--txt-only] [--page-breaks] [--lang ko,en] [--recognition-level accurate|fast] [--page-parallelism 1-16] [--render-scale 1.25|1.5|2.0] [--dry-run]
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
      --dry-run                  Validate arguments and print the output path without writing.
      --help                     Show this help text.
      --version                  Show the version.
    """
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
