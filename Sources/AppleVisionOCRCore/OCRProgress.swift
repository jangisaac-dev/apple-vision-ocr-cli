import Foundation

public enum OCRProgressStage: String, Codable, Equatable {
    case starting
    case countingPages
    case renderingPage
    case recognizingText
    case writingOutput
    case paused
    case canceled
    case completed
    case failed
}

public struct OCRProgressEvent: Codable, Equatable {
    public let stage: OCRProgressStage
    public let currentFile: String?
    public let completedPages: Int
    public let totalPages: Int
    public let message: String

    public var percent: Int {
        guard totalPages > 0 else {
            return 0
        }
        let rawPercent = Double(completedPages) / Double(totalPages) * 100
        return min(100, max(0, Int(rawPercent.rounded(.down))))
    }

    public init(
        stage: OCRProgressStage,
        currentFile: String?,
        completedPages: Int,
        totalPages: Int,
        message: String
    ) {
        self.stage = stage
        self.currentFile = currentFile
        self.completedPages = completedPages
        self.totalPages = totalPages
        self.message = message
    }
}

public final class OCRJobControl {
    private let condition = NSCondition()
    private var paused = false
    private var canceled = false

    public init() {}

    public func pause() {
        condition.withLock {
            paused = true
        }
    }

    public func resume() {
        condition.withLock {
            paused = false
            condition.broadcast()
        }
    }

    public func cancel() {
        condition.withLock {
            canceled = true
            paused = false
            condition.broadcast()
        }
    }

    public var isPaused: Bool {
        condition.withLock {
            paused
        }
    }

    public var isCanceled: Bool {
        condition.withLock {
            canceled
        }
    }

    public func waitIfPaused(onPaused: () -> Void = {}) throws {
        condition.lock()
        defer { condition.unlock() }

        var reportedPause = false
        while paused && !canceled {
            if !reportedPause {
                reportedPause = true
                onPaused()
            }
            condition.wait()
        }

        if canceled {
            throw AppleVisionOCRError.pdfFailure("OCR job canceled")
        }
    }
}

private extension NSCondition {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
