import CoreGraphics
import Foundation
import Vision

struct RecognizedTextBox {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

protocol TextRecognizing {
    func recognize(
        image: CGImage,
        languages: [String],
        recognitionLevel: OCRRecognitionLevel
    ) throws -> [RecognizedTextBox]
}

final class VisionTextRecognizer: TextRecognizing {
    func recognize(
        image: CGImage,
        languages: [String],
        recognitionLevel: OCRRecognitionLevel
    ) throws -> [RecognizedTextBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel.visionLevel
        request.recognitionLanguages = VisionLanguageResolver.resolve(languages)
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw AppleVisionOCRError.visionFailure(error.localizedDescription)
        }

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            return RecognizedTextBox(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }
}
