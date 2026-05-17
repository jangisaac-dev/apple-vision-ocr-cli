import Foundation
import PDFKit

public struct PDFTextPresenceReport: Equatable {
    public let textPageNumbers: [Int]

    public var hasText: Bool {
        !textPageNumbers.isEmpty
    }
}

public final class PDFTextPresenceDetector {
    public init() {}

    public func inspect(_ url: URL) throws -> PDFTextPresenceReport {
        guard let document = PDFDocument(url: url) else {
            throw AppleVisionOCRError.pdfFailure("failed to inspect PDF text: \(url.path)")
        }

        var textPageNumbers: [Int] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }
            if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textPageNumbers.append(pageIndex + 1)
            }
        }

        return PDFTextPresenceReport(textPageNumbers: textPageNumbers)
    }
}
