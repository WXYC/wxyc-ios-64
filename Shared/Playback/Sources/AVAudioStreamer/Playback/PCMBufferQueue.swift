@preconcurrency import AVFoundation
import DequeModule

/// Thread-safe queue for managing PCM audio buffers
final class PCMBufferQueue: @unchecked Sendable {
    private let capacity: Int
    private let minimumBuffersBeforePlayback: Int
    private let lock = NSLock()
    private var buffers: Deque<AVAudioPCMBuffer> = []

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

    init(capacity: Int, minimumBuffersBeforePlayback: Int) {
        self.capacity = capacity
        self.minimumBuffersBeforePlayback = minimumBuffersBeforePlayback
    }

    /// Enqueue a buffer. If the queue is full, the oldest buffer is removed.
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        if buffers.count >= capacity {
            buffers.removeFirst()
        }
        buffers.append(buffer)
        lock.unlock()
    }

    /// Dequeue the next buffer
    func dequeue() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffers.isEmpty else { return nil }
        return buffers.removeFirst()
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
    }
}
