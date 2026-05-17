import Foundation

public enum OutputPathResolver {
    public static func defaultOutputURL(for inputURL: URL) throws -> URL {
        guard inputURL.pathExtension.lowercased() == "pdf" else {
            throw AppleVisionOCRError.inputFileProblem("input must be a PDF: \(inputURL.path)")
        }

        let directory = inputURL.deletingLastPathComponent()
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        return directory
            .appendingPathComponent("\(baseName)_ocr")
            .appendingPathExtension("pdf")
    }

    public static func defaultTextOutputURL(for inputURL: URL) throws -> URL {
        guard inputURL.pathExtension.lowercased() == "pdf" else {
            throw AppleVisionOCRError.inputFileProblem("input must be a PDF: \(inputURL.path)")
        }

        let directory = inputURL.deletingLastPathComponent()
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        return directory
            .appendingPathComponent(baseName)
            .appendingPathExtension("txt")
    }
}
