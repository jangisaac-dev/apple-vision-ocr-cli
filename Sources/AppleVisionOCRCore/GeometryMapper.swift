import CoreGraphics
import Foundation

public struct PDFPageGeometry: Equatable {
    public let mediaBox: CGRect
    public let rotation: Int
    public let displayBox: CGRect

    public init(mediaBox: CGRect, rotation: Int) {
        let normalizedRotation = ((rotation % 360) + 360) % 360
        self.mediaBox = mediaBox
        self.rotation = normalizedRotation

        self.displayBox = CGRect(x: 0, y: 0, width: mediaBox.width, height: mediaBox.height)
    }
}

public enum GeometryMapper {
    public static func map(normalizedBox: CGRect, in geometry: PDFPageGeometry) -> CGRect {
        let page = geometry.displayBox
        return CGRect(
            x: page.minX + normalizedBox.minX * page.width,
            y: page.minY + normalizedBox.minY * page.height,
            width: normalizedBox.width * page.width,
            height: normalizedBox.height * page.height
        )
    }
}
