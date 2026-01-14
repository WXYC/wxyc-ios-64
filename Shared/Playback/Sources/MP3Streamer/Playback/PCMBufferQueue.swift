//
//  PCMBufferQueue.swift
//  Playback
//
//  Thread-safe queue for PCM audio buffers.
//
//  Created by Jake Bromberg on 12/07/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

@preconcurrency import AVFoundation
import Core
import os.lock

/// Result of enqueueing a buffer, providing queue state in a single lock acquisition.
struct EnqueueResult: Sendable {
    let count: Int
    let hasMinimumBuffers: Bool
}

/// Thread-safe queue for managing PCM audio buffers.
/// Uses os_unfair_lock for minimal lock overhead on hot paths.
final class PCMBufferQueue: @unchecked Sendable {
    private let capacity: Int
    private let minimumBuffersBeforePlayback: Int
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var buffers: Deque<AVAudioPCMBuffer> = []

    var count: Int {
        os_unfair_lock_lock(lock)
        let result = buffers.count
        os_unfair_lock_unlock(lock)
        return result
    }

    var hasMinimumBuffers: Bool {
        os_unfair_lock_lock(lock)
        let result = buffers.count >= minimumBuffersBeforePlayback
        os_unfair_lock_unlock(lock)
        return result
    }

    var isEmpty: Bool {
        os_unfair_lock_lock(lock)
        let result = buffers.isEmpty
        os_unfair_lock_unlock(lock)
        return result
    }

    init(capacity: Int, minimumBuffersBeforePlayback: Int) {
        self.capacity = capacity
        self.minimumBuffersBeforePlayback = minimumBuffersBeforePlayback
        self.lock = .allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Enqueue a buffer and return queue state in a single lock acquisition.
    /// If the queue is full, the oldest buffer is removed.
    @discardableResult
    func enqueue(_ buffer: AVAudioPCMBuffer) -> EnqueueResult {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if buffers.count >= capacity {
            buffers.removeFirst()
        }
        buffers.append(buffer)
        return EnqueueResult(
            count: buffers.count,
            hasMinimumBuffers: buffers.count >= minimumBuffersBeforePlayback
        )
    }

    /// Dequeue the next buffer
    func dequeue() -> AVAudioPCMBuffer? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard !buffers.isEmpty else { return nil }
        return buffers.removeFirst()
    }

    /// Dequeue all available buffers at once (more efficient for batch scheduling)
    func dequeueAll() -> [AVAudioPCMBuffer] {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        let result = Array(buffers)
        buffers.removeAll()
        return result
    }

    /// Peek at the next buffer without removing it
    func peek() -> AVAudioPCMBuffer? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return buffers.first
    }

    /// Clear all buffers
    func clear() {
        os_unfair_lock_lock(lock)
        buffers.removeAll()
        os_unfair_lock_unlock(lock)
    }
}
