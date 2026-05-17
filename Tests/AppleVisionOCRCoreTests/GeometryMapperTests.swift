import XCTest
@testable import AppleVisionOCRCore

final class GeometryMapperTests: XCTestCase {
    func testMapsNormalizedVisionRectToPDFDisplayCoordinates() {
        let geometry = PDFPageGeometry(
            mediaBox: CGRect(x: 0, y: 0, width: 200, height: 100),
            rotation: 0
        )

        let rect = GeometryMapper.map(
            normalizedBox: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.40),
            in: geometry
        )

        XCTAssertEqual(rect.minX, 20, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 20, accuracy: 0.001)
        XCTAssertEqual(rect.width, 60, accuracy: 0.001)
        XCTAssertEqual(rect.height, 40, accuracy: 0.001)
    }

    func testRotationNinetyPreservesMediaBoxDimensionsForOutputCoordinates() {
        let geometry = PDFPageGeometry(
            mediaBox: CGRect(x: 0, y: 0, width: 200, height: 100),
            rotation: 90
        )

        let rect = GeometryMapper.map(
            normalizedBox: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.40),
            in: geometry
        )

        XCTAssertEqual(geometry.displayBox.width, 200, accuracy: 0.001)
        XCTAssertEqual(geometry.displayBox.height, 100, accuracy: 0.001)
        XCTAssertEqual(rect.minX, 20, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 20, accuracy: 0.001)
        XCTAssertEqual(rect.width, 60, accuracy: 0.001)
        XCTAssertEqual(rect.height, 40, accuracy: 0.001)
    }
}
