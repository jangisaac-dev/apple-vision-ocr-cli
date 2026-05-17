import Foundation

public final class OCRParallelismLimiter {
    private let condition = NSCondition()
    private var limit: Int
    private var activeCount = 0

    public init(parallelism: OCRJobParallelism) {
        self.limit = parallelism.count
    }

    public var currentLimit: Int {
        condition.withLock {
            limit
        }
    }

    public func updateLimit(_ parallelism: OCRJobParallelism) {
        condition.withLock {
            limit = parallelism.count
            condition.broadcast()
        }
    }

    public func acquire(shouldCancel: () -> Bool = { false }) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        while activeCount >= limit && !shouldCancel() {
            condition.wait(until: Date(timeIntervalSinceNow: 0.1))
        }

        guard !shouldCancel() else {
            return false
        }

        activeCount += 1
        return true
    }

    public func tryAcquire() -> Bool {
        condition.withLock {
            guard activeCount < limit else {
                return false
            }
            activeCount += 1
            return true
        }
    }

    public func release() {
        condition.withLock {
            if activeCount > 0 {
                activeCount -= 1
            }
            condition.broadcast()
        }
    }

    public func wakeWaiters() {
        condition.withLock {
            condition.broadcast()
        }
    }
}

private extension NSCondition {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
