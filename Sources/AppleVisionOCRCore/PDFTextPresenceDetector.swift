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

    public func inspect(_ url: URL, pageNumbers: [Int]? = nil) throws -> PDFTextPresenceReport {
        guard let document = PDFDocument(url: url) else {
            throw AppleVisionOCRError.pdfFailure("failed to inspect PDF text: \(url.path)")
        }

        var textPageNumbers: [Int] = []
        let inspectedPageNumbers = pageNumbers ?? (0..<document.pageCount).map { $0 + 1 }
        for pageNumber in inspectedPageNumbers {
            guard pageNumber > 0, let page = document.page(at: pageNumber - 1) else {
                continue
            }
            if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textPageNumbers.append(pageNumber)
            }
        }

        return PDFTextPresenceReport(textPageNumbers: textPageNumbers)
    }
}
