import CoreGraphics
import CoreML
import XCTest
@testable import AppleVisionOCRCore

final class LayoutModelTests: XCTestCase {
    func testExplicitMissingOverrideDoesNotFallBack() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = directory.appendingPathComponent("Resources/PPDocLayoutV3.mlmodelc")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        XCTAssertNil(LayoutModel.locate(environment: ["APPLE_VISION_OCR_LAYOUT_MODEL": directory.appendingPathComponent("missing").path],
                                       executableURL: directory.appendingPathComponent("bin/ocr")))
        XCTAssertThrowsError(try LayoutModel.load(environment: ["APPLE_VISION_OCR_LAYOUT_MODEL": "/missing-layout-model"], executableURL: nil)) {
            XCTAssertEqual($0 as? AppleVisionOCRError, .visionFailure(LayoutModel.missingMessage))
        }
    }

    func testLocatesModelRelativeToResolvedExecutableSymlink() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("real/bin/ocr")
        let model = directory.appendingPathComponent("real/Resources/PPDocLayoutV3.mlmodelc")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data().write(to: executable)
        let link = directory.appendingPathComponent("ocr-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
        XCTAssertEqual(LayoutModel.locate(environment: [:], executableURL: link)?.path, model.path)
        XCTAssertEqual(LayoutModel.locate(environment: ["APPLE_VISION_OCR_LAYOUT_MODEL": model.path], executableURL: nil)?.path, model.path)
    }

    func testInputUsesRGBChannelsAndFloat16Tensor() throws {
        let bytes: [UInt8] = [255, 128, 0, 255]
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let tensor = try LayoutModel.input(image)
        XCTAssertEqual(tensor.dataType, .float16)
        XCTAssertEqual(tensor.shape.map(\.intValue), [1, 3, 800, 800])
        XCTAssertEqual(tensor[[0, 0, 400, 400]].floatValue, 1)
        XCTAssertEqual(tensor[[0, 1, 400, 400]].floatValue, 128 / 255, accuracy: 0.001)
        XCTAssertEqual(tensor[[0, 2, 400, 400]].floatValue, 0)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
