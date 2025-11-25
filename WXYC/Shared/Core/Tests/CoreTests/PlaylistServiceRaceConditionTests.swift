//
//  PlaylistServiceRaceConditionTests.swift
//  WXYC
//
//  Unit tests to verify PlaylistService doesn't start multiple fetch tasks
//

import Testing
@testable import Core

/// Mock protocol-based fetcher for tracking concurrency
actor ConcurrentTrackingMockFetcher: PlaylistFetcher {
    var activeFetchCount: Int = 0
    var maxConcurrentFetches: Int = 0
    var totalFetchCount: Int = 0

    func getPlaylist() async throws -> Playlist {
        // Track entry into fetch
        activeFetchCount += 1
        totalFetchCount += 1
        maxConcurrentFetches = max(maxConcurrentFetches, activeFetchCount)

        // Simulate network delay to increase race window
        try await Task.sleep(for: .milliseconds(50))

        // Track exit from fetch
        activeFetchCount -= 1

        return Playlist.empty
    }

    func reset() {
        activeFetchCount = 0
        maxConcurrentFetches = 0
        totalFetchCount = 0
    }
}

/// Wrapper RemotePlaylistFetcher for race condition testing
final class TrackingRemotePlaylistFetcher: RemotePlaylistFetcher, @unchecked Sendable {
    let tracker: ConcurrentTrackingMockFetcher

    init(tracker: ConcurrentTrackingMockFetcher) {
        self.tracker = tracker
        super.init(remoteFetcher: tracker)
    }
}

@Suite("PlaylistService Race Condition Tests")
struct PlaylistServiceRaceConditionTests {

    @Test("Concurrent observers start only one fetch task")
    func concurrentObserversStartOnlyOneFetchTask() async throws {
        // Given: A playlist service with a mock fetcher
        let tracker = ConcurrentTrackingMockFetcher()
        let fetcher = TrackingRemotePlaylistFetcher(tracker: tracker)
        let service = PlaylistService(
            fetcher: fetcher,
            interval: 1.0 // Short interval for testing
        )

        // When: Many observers subscribe concurrently and consume values
        let observerCount = 50
        var tasks: [Task<Void, Never>] = []
        for _ in 0..<observerCount {
            let task = Task {
                var iterator = service.updates().makeAsyncIterator()
                // Consume first value and keep stream alive
                _ = await iterator.next()
                // Keep alive briefly
                try? await Task.sleep(for: .milliseconds(200))
            }
            tasks.append(task)
        }

        // Give the fetch tasks time to start
        try await Task.sleep(for: .milliseconds(100))

        // Then: Only one fetch task should be running
        let maxConcurrent = await tracker.maxConcurrentFetches

        // Wait for all tasks to complete
        for task in tasks {
            await task.value
        }

        #expect(
            maxConcurrent == 1,
            "Expected only 1 concurrent fetch, but found \(maxConcurrent). This indicates multiple fetch tasks were started."
        )
    }

    @Test("Fetch task stops when all observers disconnect")
    func fetchTaskStopsWhenAllObserversDisconnect() async throws {
        let tracker = ConcurrentTrackingMockFetcher()
        let fetcher = TrackingRemotePlaylistFetcher(tracker: tracker)
        let service = PlaylistService(
            fetcher: fetcher,
            interval: 0.5
        )

        // Create some observers
        var tasks: [Task<Void, Never>] = []
        for _ in 0..<5 {
            let task = Task {
                for await _ in service.updates() {
                    // Consume one value then break
                    break
                }
            }
            tasks.append(task)
        }

        // Wait for initial fetches
        try await Task.sleep(for: .milliseconds(100))
        await tracker.reset()

        // Cancel all observers
        for task in tasks {
            task.cancel()
        }

        // Wait for cleanup
        try await Task.sleep(for: .milliseconds(100))

        // Wait longer than the fetch interval
        try await Task.sleep(for: .milliseconds(600))

        // Verify no more fetches occurred
        let fetchesAfterDisconnect = await tracker.totalFetchCount
        #expect(
            fetchesAfterDisconnect == 0,
            "Expected no fetches after all observers disconnected, but found \(fetchesAfterDisconnect)"
        )
    }

    @Test("Observers receive initial value")
    func observersReceiveInitialValue() async throws {
        let tracker = ConcurrentTrackingMockFetcher()
        let fetcher = TrackingRemotePlaylistFetcher(tracker: tracker)
        let service = PlaylistService(
            fetcher: fetcher,
            interval: 1.0
        )

        let stream = service.updates()
        var iterator = stream.makeAsyncIterator()

        // Should receive a value (will wait for first fetch since cache is empty)
        let firstValue = await iterator.next()
        #expect(firstValue != nil, "Expected to receive initial playlist value")
    }
}
