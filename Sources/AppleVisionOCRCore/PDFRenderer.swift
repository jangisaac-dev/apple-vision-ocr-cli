import CoreGraphics
import Foundation

struct RenderedPDFPage {
    let image: CGImage
    let geometry: PDFPageGeometry
}

protocol PDFRendering {
    func render(page: CGPDFPage, scale: OCRRenderScale) throws -> RenderedPDFPage
}

final class PDFRenderer: PDFRendering {
    func render(page: CGPDFPage, scale renderScale: OCRRenderScale) throws -> RenderedPDFPage {
        let scale = CGFloat(renderScale.value)
        let mediaBox = page.getBoxRect(.mediaBox)
        let geometry = PDFPageGeometry(mediaBox: mediaBox, rotation: Int(page.rotationAngle))
        let displaySize = geometry.displayBox.size

        let pixelWidth = max(1, Int((displaySize.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((displaySize.height * scale).rounded(.up)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AppleVisionOCRError.pdfFailure("failed to create bitmap context")
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)

        let drawRect = CGRect(origin: .zero, size: displaySize)
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: drawRect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)

        guard let image = context.makeImage() else {
            throw AppleVisionOCRError.pdfFailure("failed to render PDF page")
        }

        return RenderedPDFPage(image: image, geometry: geometry)
    }
}
