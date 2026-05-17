import Foundation

final class TextOutputWriter {
    func write(pages: [PDFPageOCRResult], includePageBreaks: Bool, to outputURL: URL) throws {
        let text = render(pages: pages, includePageBreaks: includePageBreaks)
        do {
            try text.write(to: outputURL, atomically: true, encoding: .utf8)
        } catch {
            throw AppleVisionOCRError.pdfFailure("failed to write text output: \(outputURL.path)")
        }
    }

    func render(pages: [PDFPageOCRResult], includePageBreaks: Bool) -> String {
        let pageTexts = pages.map { page -> String in
            let body = page.overlays
                .map(\.text)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            if includePageBreaks {
                return "===== Page \(page.pageNumber) =====\n\n\(body)"
            }
            return body
        }

        return pageTexts.joined(separator: "\n\n") + "\n"
    }
}
