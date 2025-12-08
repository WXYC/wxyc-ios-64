@preconcurrency import AVFoundation

/// Delegate for buffer queue events
protocol PCMBufferQueueDelegate: AnyObject, Sendable {
    /// Called when buffer level changes significantly
    func bufferQueue(_ queue: PCMBufferQueue, didChangeBufferLevel level: Int, capacity: Int)

    /// Called when the queue reaches minimum buffer threshold
    func bufferQueueDidReachMinimumThreshold(_ queue: PCMBufferQueue)

    /// Called when a buffer is dequeued
    func bufferQueue(_ queue: PCMBufferQueue, didDequeue buffer: AVAudioPCMBuffer)
}

/// Thread-safe queue for managing PCM audio buffers
final class PCMBufferQueue: @unchecked Sendable {
    private let capacity: Int
    private let minimumBuffersBeforePlayback: Int
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private weak var delegate: (any PCMBufferQueueDelegate)?

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffers.count
    }

    var hasMinimumBuffers: Bool {
        count >= minimumBuffersBeforePlayback
    }

    var isEmpty: Bool {
        count == 0
    }

    init(capacity: Int, minimumBuffersBeforePlayback: Int, delegate: (any PCMBufferQueueDelegate)?) {
        self.capacity = capacity
        self.minimumBuffersBeforePlayback = minimumBuffersBeforePlayback
        self.delegate = delegate
    }

    /// Enqueue a buffer. If the queue is full, the oldest buffer is removed.
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        lock.lock()

        // If at capacity, remove oldest buffer
        if buffers.count >= capacity {
            buffers.removeFirst()
        }

        buffers.append(buffer)
        let currentCount = buffers.count
        lock.unlock()

        // Notify delegate of buffer level change
        notifyDelegate { [weak self, capacity] in
            guard let self = self else { return }
            self.delegate?.bufferQueue(self, didChangeBufferLevel: currentCount, capacity: capacity)

            if currentCount >= self.minimumBuffersBeforePlayback {
                self.delegate?.bufferQueueDidReachMinimumThreshold(self)
            }
        }
    }

    /// Dequeue the next buffer
    func dequeue() -> AVAudioPCMBuffer? {
        lock.lock()
        guard !buffers.isEmpty else {
            lock.unlock()
            return nil
        }

        let buffer = buffers.removeFirst()
        let currentCount = buffers.count
        lock.unlock()

        // Notify delegate
        notifyDelegate { [weak self, capacity] in
            guard let self = self else { return }
            self.delegate?.bufferQueue(self, didChangeBufferLevel: currentCount, capacity: capacity)
            self.delegate?.bufferQueue(self, didDequeue: buffer)
        }

        return buffer
    }

    /// Peek at the next buffer without removing it
    func peek() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return buffers.first
    }

    /// Clear all buffers
    func clear() {
        lock.lock()
        buffers.removeAll()
        lock.unlock()

        notifyDelegate { [weak self, capacity] in
            guard let self = self else { return }
            self.delegate?.bufferQueue(self, didChangeBufferLevel: 0, capacity: capacity)
        }
    }

    private func notifyDelegate(_ closure: @Sendable @escaping () -> Void) {
        Task { @MainActor in
            closure()
        }
    }
}
