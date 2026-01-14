import Testing
import PlaybackTestUtilities
import Foundation
@preconcurrency import AVFoundation
@testable import MP3StreamerModule

#if !os(watchOS)

@Suite("PCMBufferQueue Tests")
struct PCMBufferQueueTests {

    // MARK: - Basic Functionality Tests

    @Test("Queue initializes empty")
    func testInitialization() {
        let queue = PCMBufferQueue(capacity: 10, minimumBuffersBeforePlayback: 5)

        #expect(queue.count == 0)
        #expect(queue.isEmpty == true)
        #expect(queue.hasMinimumBuffers == false)
    }

    @Test("Enqueue adds buffer and returns correct state")
    func testEnqueueReturnsState() {
        let queue = PCMBufferQueue(capacity: 10, minimumBuffersBeforePlayback: 3)
        let buffer = TestAudioBufferFactory.makeSilentBuffer()

        let result = queue.enqueue(buffer)

        #expect(result.count == 1)
        #expect(result.hasMinimumBuffers == false)
        #expect(queue.count == 1)
    }

    @Test("Enqueue returns hasMinimumBuffers when threshold reached")
    func testEnqueueReturnsHasMinimumBuffers() {
        let queue = PCMBufferQueue(capacity: 10, minimumBuffersBeforePlayback: 3)

        // Add buffers until we reach minimum
        var result = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        #expect(result.count == 1)
        #expect(result.hasMinimumBuffers == false)

        result = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        #expect(result.count == 2)
        #expect(result.hasMinimumBuffers == false)

        result = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        #expect(result.count == 3)
        #expect(result.hasMinimumBuffers == true)  // Now at minimum

        result = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        #expect(result.count == 4)
        #expect(result.hasMinimumBuffers == true)  // Still above minimum
    }

    @Test("Enqueue respects capacity and drops oldest buffer")
    func testEnqueueDropsOldestWhenFull() {
        let queue = PCMBufferQueue(capacity: 3, minimumBuffersBeforePlayback: 1)

        // Fill the queue
        _ = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        _ = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        let result1 = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        #expect(result1.count == 3)

        // Add one more - should drop oldest
        let result2 = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        #expect(result2.count == 3)  // Still at capacity
    }

    // MARK: - Dequeue Tests

    @Test("DequeueAll returns all buffers and empties queue")
    func testDequeueAll() {
        let queue = PCMBufferQueue(capacity: 10, minimumBuffersBeforePlayback: 3)

        _ = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        _ = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        _ = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())

        #expect(queue.count == 3)

        let buffers = queue.dequeueAll()

        #expect(buffers.count == 3)
        #expect(queue.count == 0)
        #expect(queue.isEmpty == true)
    }

    @Test("DequeueAll on empty queue returns empty array")
    func testDequeueAllEmpty() {
        let queue = PCMBufferQueue(capacity: 10, minimumBuffersBeforePlayback: 3)

        let buffers = queue.dequeueAll()

        #expect(buffers.isEmpty)
    }

    @Test("Clear removes all buffers")
    func testClear() {
        let queue = PCMBufferQueue(capacity: 10, minimumBuffersBeforePlayback: 3)

        _ = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        _ = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())

        #expect(queue.count == 2)

        queue.clear()

        #expect(queue.count == 0)
        #expect(queue.isEmpty == true)
    }

    // MARK: - Single Lock Acquisition Tests

    @Test("EnqueueResult provides all state in single call")
    func testEnqueueResultProvidesSingleLockState() {
        // This test verifies the optimization: instead of calling
        // enqueue() + hasMinimumBuffers separately (2 locks),
        // we get both from the EnqueueResult (1 lock)
        let queue = PCMBufferQueue(capacity: 10, minimumBuffersBeforePlayback: 2)

        let result1 = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        // Without separate calls to count or hasMinimumBuffers,
        // we have all the info we need:
        #expect(result1.count == 1)
        #expect(result1.hasMinimumBuffers == false)

        let result2 = queue.enqueue(TestAudioBufferFactory.makeSilentBuffer())
        #expect(result2.count == 2)
        #expect(result2.hasMinimumBuffers == true)

        // Verify the queue state matches what EnqueueResult reported
        #expect(queue.count == result2.count)
        #expect(queue.hasMinimumBuffers == result2.hasMinimumBuffers)
    }
}

#endif // !os(watchOS)
