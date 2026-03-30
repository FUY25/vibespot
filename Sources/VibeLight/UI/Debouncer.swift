import Foundation

final class Debouncer: @unchecked Sendable {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var workItem: DispatchWorkItem?

    init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    func schedule(_ action: @escaping @Sendable () -> Void) {
        let item = DispatchWorkItem(block: action)

        lock.lock()
        workItem?.cancel()
        workItem = item
        lock.unlock()

        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        lock.lock()
        workItem?.cancel()
        workItem = nil
        lock.unlock()
    }
}
