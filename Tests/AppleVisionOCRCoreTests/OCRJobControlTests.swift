import XCTest
@testable import AppleVisionOCRCore

final class OCRJobControlTests: XCTestCase {
    func testPauseResumeCancelFlags() {
        let control = OCRJobControl()

        XCTAssertFalse(control.isPaused)
        XCTAssertFalse(control.isCanceled)

        control.pause()
        XCTAssertTrue(control.isPaused)

        control.resume()
        XCTAssertFalse(control.isPaused)

        control.cancel()
        XCTAssertTrue(control.isCanceled)
        XCTAssertFalse(control.isPaused)
    }

    func testCancelUnblocksPausedWaiter() {
        let control = OCRJobControl()
        control.pause()
        let waiter = expectation(description: "waiter exits")

        DispatchQueue.global().async {
            do {
                try control.waitIfPaused()
                XCTFail("expected cancellation")
            } catch {
                // Expected.
            }
            waiter.fulfill()
        }

        control.cancel()
        wait(for: [waiter], timeout: 1)
    }
}
