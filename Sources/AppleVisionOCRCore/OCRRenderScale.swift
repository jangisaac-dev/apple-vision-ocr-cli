import Foundation

public enum OCRRenderScale: Equatable {
    case compact
    case balanced
    case quality

    public var value: Double {
        switch self {
        case .compact:
            return 1.25
        case .balanced:
            return 1.5
        case .quality:
            return 2.0
        }
    }

    public static func parse(_ rawValue: String) throws -> OCRRenderScale {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1.25", "compact":
            return .compact
        case "1.5", "balanced":
            return .balanced
        case "2", "2.0", "quality":
            return .quality
        default:
            throw AppleVisionOCRError.invalidUsage("render scale must be 1.25, 1.5, or 2.0")
        }
    }
}
