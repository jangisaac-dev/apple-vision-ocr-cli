import CoreGraphics
import CoreText
import Foundation

struct PDFTextOverlay {
    let text: String
    let rect: CGRect
}

struct PDFPageOCRResult {
    let pageNumber: Int
    let geometry: PDFPageGeometry
    let overlays: [PDFTextOverlay]
    let backgroundImage: CGImage?

    init(
        pageNumber: Int,
        geometry: PDFPageGeometry,
        overlays: [PDFTextOverlay],
        backgroundImage: CGImage? = nil
    ) {
        self.pageNumber = pageNumber
        self.geometry = geometry
        self.overlays = overlays
        self.backgroundImage = backgroundImage
    }
}

final class PDFTextOverlayWriter {
    static func horizontalScale(lineWidth: CGFloat, rectWidth: CGFloat) -> CGFloat {
        guard lineWidth > 0, rectWidth > 0 else {
            return 1
        }
        return rectWidth / lineWidth
    }

    func write(sourceDocument: CGPDFDocument, pages: [PDFPageOCRResult], to outputURL: URL) throws {
        guard let context = CGContext(outputURL as CFURL, mediaBox: nil, nil) else {
            throw AppleVisionOCRError.pdfFailure("failed to create output PDF: \(outputURL.path)")
        }

        for pageResult in pages {
            guard let sourcePage = sourceDocument.page(at: pageResult.pageNumber) else {
                throw AppleVisionOCRError.pdfFailure("source page missing: \(pageResult.pageNumber)")
            }

            var mediaBox = pageResult.geometry.mediaBox
            let pageInfo = withUnsafeBytes(of: &mediaBox) { bytes -> CFDictionary in
                [kCGPDFContextMediaBox as String: Data(bytes)] as CFDictionary
            }
            context.beginPDFPage(pageInfo)
            if let backgroundImage = pageResult.backgroundImage {
                drawBackgroundImage(backgroundImage, geometry: pageResult.geometry, into: context)
            } else {
                drawOriginalPage(sourcePage, geometry: pageResult.geometry, into: context)
            }

            for overlay in pageResult.overlays where !overlay.text.isEmpty {
                drawInvisibleText(overlay.text, in: overlay.rect, into: context)
            }

            context.endPDFPage()
        }

        context.closePDF()
    }

    private func drawOriginalPage(_ page: CGPDFPage, geometry: PDFPageGeometry, into context: CGContext) {
        context.saveGState()
        let drawRect = CGRect(origin: .zero, size: geometry.mediaBox.size)
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: drawRect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        context.restoreGState()
    }

    private func drawBackgroundImage(_ image: CGImage, geometry: PDFPageGeometry, into context: CGContext) {
        context.saveGState()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        let drawRect = CGRect(origin: .zero, size: geometry.mediaBox.size)
        context.fill(drawRect)
        context.draw(image, in: drawRect)
        context.restoreGState()
    }

    private func drawInvisibleText(_ text: String, in rect: CGRect, into context: CGContext) {
        let fontSize = max(1, rect.height * 0.8)
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 0)
        ] as CFDictionary

        guard let attributedText = CFAttributedStringCreate(nil, text as CFString, attributes) else {
            return
        }

        let line = CTLineCreateWithAttributedString(attributedText)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let horizontalScale = Self.horizontalScale(lineWidth: lineWidth, rectWidth: rect.width)
        let baselineY = max(descent, (rect.height - ascent - descent) / 2 + descent)

        context.saveGState()
        context.textMatrix = .identity
        context.setTextDrawingMode(.invisible)
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: horizontalScale, y: 1)
        context.textPosition = CGPoint(x: 0, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
