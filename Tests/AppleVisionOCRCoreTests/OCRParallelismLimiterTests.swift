import XCTest
@testable import AppleVisionOCRCore

final class OCRParallelismLimiterTests: XCTestCase {
    func testIncreasingLimitAllowsAdditionalAcquire() throws {
        let limiter = OCRParallelismLimiter(parallelism: try OCRJobParallelism(count: 1))

        XCTAssertTrue(limiter.tryAcquire())
        XCTAssertFalse(limiter.tryAcquire())

        limiter.updateLimit(try OCRJobParallelism(count: 2))

        XCTAssertTrue(limiter.tryAcquire())

        limiter.release()
        limiter.release()
    }

    func testDecreasingLimitBlocksNewAcquireUntilActiveCountFallsBelowLimit() throws {
        let limiter = OCRParallelismLimiter(parallelism: try OCRJobParallelism(count: 2))

        XCTAssertTrue(limiter.tryAcquire())
        XCTAssertTrue(limiter.tryAcquire())

        limiter.updateLimit(try OCRJobParallelism(count: 1))

        XCTAssertFalse(limiter.tryAcquire())
        limiter.release()
        XCTAssertFalse(limiter.tryAcquire())
        limiter.release()
        XCTAssertTrue(limiter.tryAcquire())

        limiter.release()
    }
}
