import Foundation
import Vision

public enum OCRRecognitionLevel: String, Equatable {
    case fast
    case accurate

    public static func parse(_ rawValue: String) throws -> OCRRecognitionLevel {
        guard let level = OCRRecognitionLevel(rawValue: rawValue.lowercased()) else {
            throw AppleVisionOCRError.invalidUsage("recognition level must be accurate or fast")
        }
        return level
    }

    var visionLevel: VNRequestTextRecognitionLevel {
        switch self {
        case .fast:
            return .fast
        case .accurate:
            return .accurate
        }
    }
}
