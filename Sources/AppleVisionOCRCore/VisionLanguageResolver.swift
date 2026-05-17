import Foundation
import Vision

enum VisionLanguageResolver {
    private static let aliases = [
        "ko": "ko-KR",
        "en": "en-US"
    ]

    static func resolve(_ languages: [String]) -> [String] {
        languages.map { aliases[$0.lowercased()] ?? $0 }
    }

    static func unsupportedLanguages(
        _ languages: [String],
        recognitionLevel: OCRRecognitionLevel
    ) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel.visionLevel
        let supportedLanguages = Set(try request.supportedRecognitionLanguages())

        return resolve(languages).filter { !supportedLanguages.contains($0) }
    }
}
