//
//  PlaylistServiceRaceConditionTests.swift
//  Playlist
//
//  Unit tests to verify PlaylistService doesn't start multiple fetch tasks
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
@testable import Caching

// MARK: - Mock Cache for Tests

/// In-memory cache for isolated test execution (race condition tests)
final class RaceConditionTestMockCache: Cache, @unchecked Sendable {
    private var dataStorage: [String: Data] = [:]
    private var metadataStorage: [String: CacheMetadata] = [:]
    private let lock = NSLock()

    func metadata(for key: String) -> CacheMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return metadataStorage[key]
    }
    
    func data(for key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return dataStorage[key]
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let data = data {
            dataStorage[key] = data
            metadataStorage[key] = metadata
        } else {
            remove(for: key)
        }
    }
    
    func remove(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        dataStorage.removeValue(forKey: key)
        metadataStorage.removeValue(forKey: key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        lock.lock()
        defer { lock.unlock() }
        return metadataStorage.map { ($0.key, $0.value) }
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        dataStorage.removeAll()
        metadataStorage.removeAll()
    }
    
    func totalSize() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return dataStorage.values.reduce(0) { $0 + Int64($1.count) }
    }
}

/// Mock fetcher for tracking concurrency in race condition tests
actor ConcurrentTrackingMockFetcher: PlaylistFetcherProtocol {
    var activeFetchCount: Int = 0
    var maxConcurrentFetches: Int = 0
    var totalFetchCount: Int = 0
    
    /// Returns a non-empty playlist so broadcasts happen
    private let testPlaylist = Playlist(
        playcuts: [
            Playcut(
                id: 1,
                hour: 1000,
                chronOrderID: 1,
                songTitle: "Test Song",
                labelName: nil,
                artistName: "Test Artist",
                releaseTitle: nil
            )
        ],
        breakpoints: [],
        talksets: []
    )

    func fetchPlaylist() async -> Playlist {
        // Track entry into fetch
        activeFetchCount += 1
        totalFetchCount += 1
        maxConcurrentFetches = max(maxConcurrentFetches, activeFetchCount)

        // Simulate network delay to increase race window
        try? await Task.sleep(for: .milliseconds(50))

        // Track exit from fetch
        activeFetchCount -= 1

        return testPlaylist
    }

    func reset() {
        activeFetchCount = 0
        maxConcurrentFetches = 0
        totalFetchCount = 0
    }
}

@Suite("PlaylistService Race Condition Tests", .serialized)
struct PlaylistServiceRaceConditionTests {

    @Test("Concurrent observers start only one fetch task", .timeLimit(.minutes(1)))
    func concurrentObserversStartOnlyOneFetchTask() async throws {
        // Given: A playlist service with a mock fetcher
        let tracker = ConcurrentTrackingMockFetcher()
        let service = PlaylistService(
            fetcher: tracker,
            interval: 1.0, // Short interval for testing
            cacheCoordinator: CacheCoordinator(cache: RaceConditionTestMockCache())
        )

        // When: Many observers subscribe concurrently and consume values
        let observerCount = 50
        var tasks: [Task<Playlist?, Never>] = []
        for _ in 0..<observerCount {
            let task = Task {
                var iterator = service.updates().makeAsyncIterator()
                // Consume first value - this ensures fetch completed
                return await iterator.next()
            }
            tasks.append(task)
        }

        // Wait for all tasks to receive a value (proves fetch completed)
        var receivedCount = 0
        for task in tasks {
            let value = await task.value
            if value != nil {
                receivedCount += 1
            }
        }

        // Verify all observers received a value
        #expect(receivedCount == observerCount, "All observers should receive a playlist")

        // Then: Only one fetch task should have been started
        let maxConcurrent = await tracker.maxConcurrentFetches
        let totalFetches = await tracker.totalFetchCount

        #expect(
            maxConcurrent == 1,
            "Expected only 1 concurrent fetch, but found \(maxConcurrent). This indicates multiple fetch tasks were started."
        )
        #expect(
            totalFetches == 1,
            "Expected only 1 total fetch, but found \(totalFetches). The fetch loop should only run once during this test."
        )
    }

    @Test("Fetch task stops when all observers disconnect", .timeLimit(.minutes(1)))
    func fetchTaskStopsWhenAllObserversDisconnect() async throws {
        let tracker = ConcurrentTrackingMockFetcher()
        let service = PlaylistService(
            fetcher: tracker,
            interval: 0.2, // Short interval to make test faster
            cacheCoordinator: CacheCoordinator(cache: RaceConditionTestMockCache())
        )

        // Create some observers that consume a value then disconnect
        var tasks: [Task<Playlist?, Never>] = []
        for _ in 0..<5 {
            let task = Task {
                var iterator = service.updates().makeAsyncIterator()
                // Consume one value - this ensures fetch completed
                return await iterator.next()
            }
            tasks.append(task)
        }

        // Wait for all tasks to complete (observers have consumed and disconnected)
        for task in tasks {
            _ = await task.value
        }

        // Record fetch count after initial fetch completed
        let fetchesBeforeWait = await tracker.totalFetchCount
        #expect(fetchesBeforeWait >= 1, "At least one fetch should have occurred")

        // Reset tracker to measure fetches after disconnect
        await tracker.reset()

        // Wait significantly longer than the fetch interval
        // If the fetch task was still running, it would fetch again
        try await Task.sleep(for: .milliseconds(500))

        // Verify no more fetches occurred after all observers disconnected
        let fetchesAfterDisconnect = await tracker.totalFetchCount
        #expect(
            fetchesAfterDisconnect == 0,
            "Expected no fetches after all observers disconnected, but found \(fetchesAfterDisconnect)"
        )
    }

    @Test("Observers receive initial value", .timeLimit(.minutes(1)))
    func observersReceiveInitialValue() async throws {
        let tracker = ConcurrentTrackingMockFetcher()
        let service = PlaylistService(
            fetcher: tracker,
            interval: 1.0,
            cacheCoordinator: CacheCoordinator(cache: RaceConditionTestMockCache())
        )
        
        // Use a Task to properly manage the stream lifecycle
        let task = Task {
            var iterator = service.updates().makeAsyncIterator()
            return await iterator.next()
        }
        
        // Should receive a value (will wait for first fetch since cache is empty)
        let firstValue = await task.value
        #expect(firstValue != nil, "Expected to receive initial playlist value")

        // Cancel the task to ensure cleanup
        task.cancel()

        // Give the service time to clean up
        try await Task.sleep(for: .milliseconds(100))
    }
}
