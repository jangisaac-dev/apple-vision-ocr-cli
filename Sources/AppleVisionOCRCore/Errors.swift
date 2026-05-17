import Foundation

public enum ExitCode: Int32 {
    case success = 0
    case invalidUsage = 1
    case inputFileProblem = 2
    case pdfFailure = 3
    case visionFailure = 4
    case outputAlreadyExists = 5
}

public enum AppleVisionOCRError: Error, Equatable {
    case invalidUsage(String)
    case inputFileProblem(String)
    case pdfFailure(String)
    case visionFailure(String)
    case outputAlreadyExists(String)

    public var exitCode: ExitCode {
        switch self {
        case .invalidUsage:
            return .invalidUsage
        case .inputFileProblem:
            return .inputFileProblem
        case .pdfFailure:
            return .pdfFailure
        case .visionFailure:
            return .visionFailure
        case .outputAlreadyExists:
            return .outputAlreadyExists
        }
    }
}

extension AppleVisionOCRError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidUsage(let message),
             .inputFileProblem(let message),
             .pdfFailure(let message),
             .visionFailure(let message),
             .outputAlreadyExists(let message):
            return message
        }
    }
}
