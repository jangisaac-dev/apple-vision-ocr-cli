import Foundation

public enum UniqueOutputPathResolver {
    public static func availablePDFOutputURL(
        for inputURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let defaultURL = try OutputPathResolver.defaultOutputURL(for: inputURL)
        return availableURL(defaultURL, fileManager: fileManager)
    }

    public static func availableTextOutputURL(
        for inputURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let defaultURL = try OutputPathResolver.defaultTextOutputURL(for: inputURL)
        return availableURL(defaultURL, fileManager: fileManager)
    }

    public static func availableURL(_ defaultURL: URL, fileManager: FileManager = .default) -> URL {
        guard fileManager.fileExists(atPath: defaultURL.path) else {
            return defaultURL
        }

        let directory = defaultURL.deletingLastPathComponent()
        let baseName = defaultURL.deletingPathExtension().lastPathComponent
        let pathExtension = defaultURL.pathExtension

        var counter = 1
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName)(\(counter))")
                .appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
