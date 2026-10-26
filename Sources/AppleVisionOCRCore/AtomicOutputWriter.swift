import Foundation

enum AtomicOutputWriter {
    static func write(_ data: Data, to outputURL: URL, fileManager: FileManager = .default) throws {
        guard !fileManager.fileExists(atPath: outputURL.path) else {
            throw AppleVisionOCRError.outputAlreadyExists("output already exists: \(outputURL.path)")
        }
        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL)
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw AppleVisionOCRError.pdfFailure("failed to write output: \(outputURL.path)")
        }
    }
}
