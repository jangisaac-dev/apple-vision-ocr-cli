import XCTest
@testable import AppleVisionOCRCore

final class UniqueOutputPathResolverTests: XCTestCase {
    func testReturnsDefaultPDFPathWhenAvailable() throws {
        let directory = try makeDirectory()
        let input = directory.appendingPathComponent("sample.pdf")
        FileManager.default.createFile(atPath: input.path, contents: Data())

        let output = try UniqueOutputPathResolver.availablePDFOutputURL(for: input)

        XCTAssertEqual(output.lastPathComponent, "sample_ocr.pdf")
    }

    func testReturnsNumberedPDFPathWhenDefaultExists() throws {
        let directory = try makeDirectory()
        let input = directory.appendingPathComponent("sample.pdf")
        let existing = directory.appendingPathComponent("sample_ocr.pdf")
        FileManager.default.createFile(atPath: input.path, contents: Data())
        FileManager.default.createFile(atPath: existing.path, contents: Data())

        let output = try UniqueOutputPathResolver.availablePDFOutputURL(for: input)

        XCTAssertEqual(output.lastPathComponent, "sample_ocr(1).pdf")
    }

    func testReturnsNumberedTextPathWhenDefaultExists() throws {
        let directory = try makeDirectory()
        let input = directory.appendingPathComponent("sample.pdf")
        let existing = directory.appendingPathComponent("sample.txt")
        FileManager.default.createFile(atPath: input.path, contents: Data())
        FileManager.default.createFile(atPath: existing.path, contents: Data())

        let output = try UniqueOutputPathResolver.availableTextOutputURL(for: input)

        XCTAssertEqual(output.lastPathComponent, "sample(1).txt")
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
