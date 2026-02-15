//
//  DelayBuffer.swift
//  PlayerHeaderView
//
//  A lock-protected FIFO ring buffer of timestamped visualization frames.
//  Used to delay visualizer output by the audio session's outputLatency,
//  synchronizing the visualizer animation with audible output on AirPlay speakers.
//
//  Created by Jake Bromberg on 02/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import os

/// A single visualization frame tagged with the time it was produced.
struct TimestampedFrame {
    let timestamp: ContinuousClock.Instant
    let fftMagnitudes: [Float]
    let rmsPerBar: [Float]
}

/// Thread-safe FIFO ring buffer that holds timestamped visualization frames
/// and releases them after a configurable delay has elapsed.
final class DelayBuffer: @unchecked Sendable {

    private let capacity: Int
    private var storage: [TimestampedFrame?]
    private var head = 0  // next write index
    private var count = 0
    private let lock = OSAllocatedUnfairLock()

    init(capacity: Int = 256) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    /// Maps a logical offset (0 = oldest) to the physical storage index.
    private func storageIndex(offset: Int) -> Int {
        ((head - count + offset) % capacity + capacity) % capacity
    }

    /// Appends a frame to the buffer, dropping the oldest if at capacity.
    func enqueue(_ frame: TimestampedFrame) {
        lock.lock()
        defer { lock.unlock() }

        storage[head] = frame
        head = (head + 1) % capacity
        if count < capacity {
            count += 1
        }
        // When count == capacity, head has just overwritten the oldest entry,
        // so count stays at capacity (oldest was implicitly dropped).
    }

    /// Returns the most recent frame whose `timestamp + delay <= now`,
    /// discarding all older eligible frames. Returns nil if no frame is ready yet.
    func dequeue(delay: TimeInterval, now: ContinuousClock.Instant) -> TimestampedFrame? {
        lock.lock()
        defer { lock.unlock() }

        let deadline = now - .seconds(delay)
        var bestIndex: Int?

        // Walk from oldest to newest, finding the latest eligible frame
        for offset in 0..<count {
            let index = storageIndex(offset: offset)
            guard let frame = storage[index] else { continue }
            if frame.timestamp <= deadline {
                bestIndex = offset  // offset from oldest
            } else {
                break  // Frames are in chronological order; no more eligible
            }
        }

        guard let best = bestIndex else { return nil }

        // The best frame is at offset `best` from the oldest.
        // Consume it and all older frames.
        let consumeCount = best + 1
        let bestAbsIndex = storageIndex(offset: best)
        let result = storage[bestAbsIndex]

        // Clear consumed slots
        for offset in 0..<consumeCount {
            storage[storageIndex(offset: offset)] = nil
        }
        count -= consumeCount

        return result
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return count == 0
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }

        for offset in 0..<count {
            storage[storageIndex(offset: offset)] = nil
        }
        count = 0
    }
}
