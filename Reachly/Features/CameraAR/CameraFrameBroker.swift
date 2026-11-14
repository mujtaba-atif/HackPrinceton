import Foundation

/// Thread-safe frame fan-out with backpressure suited to real-time vision.
/// Every subscriber gets its own stream and keeps only the newest frame, preventing inference lag.
final class CameraFrameBroker: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<CameraFrame>.Continuation] = [:]
    private var isFinished = false

    func makeStream() -> AsyncStream<CameraFrame> {
        let identifier = UUID()

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.lock()
            if isFinished {
                lock.unlock()
                continuation.finish()
                return
            }
            continuations[identifier] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(identifier)
            }
        }
    }

    func publish(_ frame: CameraFrame) {
        lock.lock()
        let activeContinuations = Array(continuations.values)
        lock.unlock()

        for continuation in activeContinuations {
            continuation.yield(frame)
        }
    }

    func finish() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let activeContinuations = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()

        for continuation in activeContinuations {
            continuation.finish()
        }
    }

    private func removeContinuation(_ identifier: UUID) {
        lock.lock()
        continuations.removeValue(forKey: identifier)
        lock.unlock()
    }
}

