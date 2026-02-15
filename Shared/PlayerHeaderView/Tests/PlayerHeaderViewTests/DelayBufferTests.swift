//
//  DelayBufferTests.swift
//  PlayerHeaderView
//
//  Tests for DelayBuffer, a lock-protected FIFO ring buffer of timestamped
//  visualization frames used to synchronize visualizer output with AirPlay latency.
//
//  Created by Jake Bromberg on 02/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import PlayerHeaderView

@Suite("DelayBuffer Tests")
struct DelayBufferTests {

    // MARK: - Empty State

    @Test("Fresh buffer is empty")
    func freshBufferIsEmpty() {
        let buffer = DelayBuffer()
        #expect(buffer.isEmpty)
    }

    // MARK: - Enqueue

    @Test("Enqueue makes buffer non-empty")
    func enqueueMakesNonEmpty() {
        let buffer = DelayBuffer()
        let frame = TimestampedFrame(
            timestamp: .now,
            fftMagnitudes: [1, 2, 3],
            rmsPerBar: [0.5]
        )
        buffer.enqueue(frame)
        #expect(!buffer.isEmpty)
    }

    // MARK: - Dequeue with zero delay

    @Test("Dequeue with zero delay returns enqueued frame")
    func dequeueZeroDelay() {
        let buffer = DelayBuffer()
        let now = ContinuousClock.Instant.now
        let frame = TimestampedFrame(
            timestamp: now,
            fftMagnitudes: [1, 2, 3],
            rmsPerBar: [0.5, 0.6]
        )
        buffer.enqueue(frame)

        let result = buffer.dequeue(delay: 0, now: now)
        #expect(result != nil)
        #expect(result?.fftMagnitudes == [1, 2, 3])
        #expect(result?.rmsPerBar == [0.5, 0.6])
        #expect(buffer.isEmpty)
    }

    // MARK: - Dequeue with delay

    @Test("Dequeue with 2s delay returns nil when frame is too recent")
    func dequeueWithDelayTooRecent() {
        let buffer = DelayBuffer()
        let now = ContinuousClock.Instant.now
        let frame = TimestampedFrame(
            timestamp: now,
            fftMagnitudes: [1],
            rmsPerBar: [0.5]
        )
        buffer.enqueue(frame)

        // Asking at the same instant with 2s delay → frame not ready
        let result = buffer.dequeue(delay: 2.0, now: now)
        #expect(result == nil)
        #expect(!buffer.isEmpty)
    }

    @Test("Dequeue with delay returns frame once enough time has passed")
    func dequeueAfterDelay() {
        let buffer = DelayBuffer()
        let now = ContinuousClock.Instant.now
        let frame = TimestampedFrame(
            timestamp: now,
            fftMagnitudes: [42],
            rmsPerBar: [0.9]
        )
        buffer.enqueue(frame)

        // 2 seconds later, with 2s delay → frame is ready
        let later = now + .seconds(2)
        let result = buffer.dequeue(delay: 2.0, now: later)
        #expect(result != nil)
        #expect(result?.fftMagnitudes == [42])
    }

    // MARK: - Skip to latest eligible

    @Test("Dequeue skips to latest eligible when multiple frames are ready")
    func dequeueSkipsToLatest() {
        let buffer = DelayBuffer()
        let t0 = ContinuousClock.Instant.now
        let t1 = t0 + .milliseconds(16)
        let t2 = t0 + .milliseconds(32)
        let t3 = t0 + .milliseconds(48)

        buffer.enqueue(TimestampedFrame(timestamp: t0, fftMagnitudes: [1], rmsPerBar: []))
        buffer.enqueue(TimestampedFrame(timestamp: t1, fftMagnitudes: [2], rmsPerBar: []))
        buffer.enqueue(TimestampedFrame(timestamp: t2, fftMagnitudes: [3], rmsPerBar: []))
        buffer.enqueue(TimestampedFrame(timestamp: t3, fftMagnitudes: [4], rmsPerBar: []))

        // At t0 + 40ms with zero delay, frames at t0..t2 are all eligible (t3 at 48ms is not yet)
        // Wait, with zero delay they're all eligible. Let's use a 20ms delay instead.
        // At t0 + 40ms with 20ms delay: eligible if timestamp + 20ms <= t0 + 40ms → timestamp <= t0 + 20ms
        // That means t0 (0ms) and t1 (16ms) are eligible. t2 (32ms) is not.
        // Should return t1 (the latest eligible) and discard t0.
        let queryTime = t0 + .milliseconds(40)
        let result = buffer.dequeue(delay: 0.020, now: queryTime)
        #expect(result?.fftMagnitudes == [2])

        // t2 and t3 should still be in the buffer
        #expect(!buffer.isEmpty)
    }

    // MARK: - Clear

    @Test("Clear empties the buffer")
    func clearEmptiesBuffer() {
        let buffer = DelayBuffer()
        let now = ContinuousClock.Instant.now
        buffer.enqueue(TimestampedFrame(timestamp: now, fftMagnitudes: [1], rmsPerBar: []))
        buffer.enqueue(TimestampedFrame(timestamp: now, fftMagnitudes: [2], rmsPerBar: []))
        buffer.enqueue(TimestampedFrame(timestamp: now, fftMagnitudes: [3], rmsPerBar: []))

        buffer.clear()
        #expect(buffer.isEmpty)
        #expect(buffer.dequeue(delay: 0, now: now) == nil)
    }

    // MARK: - Overflow

    @Test("Overflow beyond capacity drops oldest frames")
    func overflowDropsOldest() {
        let buffer = DelayBuffer(capacity: 4)
        let t0 = ContinuousClock.Instant.now

        // Enqueue 6 frames into a capacity-4 buffer
        for i in 0..<6 {
            buffer.enqueue(TimestampedFrame(
                timestamp: t0 + .milliseconds(i * 16),
                fftMagnitudes: [Float(i)],
                rmsPerBar: []
            ))
        }

        // Oldest two (0, 1) should have been dropped.
        // With zero delay at a far-future time, we should get frame 5 (the latest).
        let farFuture = t0 + .seconds(10)
        let result = buffer.dequeue(delay: 0, now: farFuture)
        #expect(result?.fftMagnitudes == [5])
        #expect(buffer.isEmpty)
    }

    // MARK: - Thread safety

    @Test("Concurrent enqueue and dequeue do not crash")
    func concurrentAccess() async {
        let buffer = DelayBuffer()
        let t0 = ContinuousClock.Instant.now

        await withTaskGroup(of: Void.self) { group in
            // Writer
            group.addTask {
                for i in 0..<1000 {
                    buffer.enqueue(TimestampedFrame(
                        timestamp: t0 + .milliseconds(i),
                        fftMagnitudes: [Float(i)],
                        rmsPerBar: []
                    ))
                }
            }

            // Reader
            group.addTask {
                for i in 0..<1000 {
                    _ = buffer.dequeue(
                        delay: 0,
                        now: t0 + .milliseconds(i)
                    )
                }
            }

            // Clearer
            group.addTask {
                for _ in 0..<100 {
                    _ = buffer.isEmpty
                    buffer.clear()
                }
            }
        }
        // Test passes if no crash
    }
}
