import Foundation

struct StoredVOCRProgress: Codable {
    let state: VOCRRunState
    let currentFile: String?
    let completedFiles: Int
    let totalFiles: Int
    let completedPages: Int
    let totalPages: Int
    let percent: Int
    let message: String
    let updatedAt: Date
}

final class ProgressStore {
    private let progressURL: URL
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VOCR/progress", isDirectory: true)
        self.progressURL = baseURL.appendingPathComponent("latest.json")
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    func write(_ snapshot: VOCRProgressSnapshot) {
        let stored = StoredVOCRProgress(
            state: snapshot.state,
            currentFile: snapshot.currentFile,
            completedFiles: snapshot.completedFiles,
            totalFiles: snapshot.totalFiles,
            completedPages: snapshot.completedPages,
            totalPages: snapshot.totalPages,
            percent: snapshot.percent,
            message: snapshot.message,
            updatedAt: Date()
        )

        do {
            try FileManager.default.createDirectory(
                at: progressURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(stored)
            try data.write(to: progressURL, options: .atomic)
        } catch {
            NSLog("VOCR progress write failed: \(error.localizedDescription)")
        }
    }
}
