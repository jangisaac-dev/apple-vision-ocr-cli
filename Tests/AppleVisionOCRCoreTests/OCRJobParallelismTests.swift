import XCTest
@testable import AppleVisionOCRCore

final class OCRJobParallelismTests: XCTestCase {
    func testDefaultParallelismUsesAvailableHeadroom() {
        XCTAssertEqual(OCRJobParallelism.default.count, 8)
    }

    func testRecommendedWorkerCountClampsToAvailableHeadroom() {
        XCTAssertEqual(OCRJobParallelism.recommendedWorkerCount(activeProcessorCount: 18), 4)
        XCTAssertEqual(OCRJobParallelism.recommendedWorkerCount(activeProcessorCount: 8), 2)
        XCTAssertEqual(OCRJobParallelism.recommendedWorkerCount(activeProcessorCount: 4), 2)
        XCTAssertEqual(OCRJobParallelism.recommendedWorkerCount(activeProcessorCount: 1), 2)
        XCTAssertEqual(OCRJobParallelism.recommendedWorkerCount(activeProcessorCount: 32), 8)
        XCTAssertEqual(OCRJobParallelism.recommendedWorkerCount(activeProcessorCount: 72), 16)
    }

    func testAcceptsPositiveParallelismWithinLimit() throws {
        let parallelism = try OCRJobParallelism(count: 16)

        XCTAssertEqual(parallelism.count, 16)
    }

    func testRejectsZeroParallelism() {
        XCTAssertThrowsError(try OCRJobParallelism(count: 0)) { error in
            XCTAssertEqual(error as? OCRJobOptionError, .invalidParallelism)
        }
    }

    func testRejectsParallelismAboveLimit() {
        XCTAssertThrowsError(try OCRJobParallelism(count: 17)) { error in
            XCTAssertEqual(error as? OCRJobOptionError, .invalidParallelism)
        }
    }
}
