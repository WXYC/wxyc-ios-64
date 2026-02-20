//
//  WidgetStateServiceRelevanceTests.swift
//  AppServices
//
//  Tests for WidgetStateService's relevance hint behavior, verifying that
//  RelevantIntents are updated when playback state changes.
//
//  Created by Claude on 02/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if canImport(WidgetKit)
import AppIntents
import AVFoundation
import Foundation
import PlaybackCore
import Testing
import WidgetKit
@testable import Caching
@testable import Playlist
@testable import AppServices

@MainActor
@Suite("WidgetStateService Relevance Tests", .timeLimit(.minutes(1)))
struct WidgetStateServiceRelevanceTests {

    // MARK: - Tests

    @Test("Relevance is set when playback becomes active")
    func relevanceSetWhenPlaybackBecomesActive() async throws {
        // Given
        let mockRelevance = MockWidgetRelevanceUpdater()
        let mockPlayback = MockPlaybackController()
        let service = WidgetStateService(
            playbackController: mockPlayback,
            playlistService: makeTestPlaylistService(),
            relevanceUpdater: mockRelevance
        )

        // Wait for init clear
        await mockRelevance.waitForCallCount(1)

        service.start()

        // Wait for initial observation delivery (idle -> clear)
        await mockRelevance.waitForCallCount(2)

        let countBeforeChange = mockRelevance.callCount

        // When
        mockPlayback.state = .playing

        // Then — wait for the relevance update
        await mockRelevance.waitForCallCount(countBeforeChange + 1)
        let lastCall = try #require(mockRelevance.lastCall)
        #expect(lastCall.count == 1)

        _ = service // retain
    }

    @Test("Relevance is cleared when playback stops")
    func relevanceClearedWhenPlaybackStops() async throws {
        // Given
        let mockRelevance = MockWidgetRelevanceUpdater()
        let mockPlayback = MockPlaybackController()
        mockPlayback.state = .playing
        let service = WidgetStateService(
            playbackController: mockPlayback,
            playlistService: makeTestPlaylistService(),
            relevanceUpdater: mockRelevance
        )

        // Wait for init clear
        await mockRelevance.waitForCallCount(1)

        service.start()

        // Wait for initial observation delivery (playing -> set)
        await mockRelevance.waitForCallCount(2)

        let countBeforeChange = mockRelevance.callCount

        // When
        mockPlayback.state = .idle

        // Then — wait for the relevance update
        await mockRelevance.waitForCallCount(countBeforeChange + 1)
        let lastCall = try #require(mockRelevance.lastCall)
        #expect(lastCall.isEmpty)

        _ = service // retain
    }

    @Test("Relevance is cleared on init")
    func relevanceClearedOnInit() async throws {
        // Given/When
        let mockRelevance = MockWidgetRelevanceUpdater()
        let mockPlayback = MockPlaybackController()
        let service = WidgetStateService(
            playbackController: mockPlayback,
            playlistService: makeTestPlaylistService(),
            relevanceUpdater: mockRelevance
        )

        // Then — wait for the init clear
        await mockRelevance.waitForCallCount(1)
        let firstCall = try #require(mockRelevance.lastCall)
        #expect(firstCall.isEmpty)

        _ = service // retain
    }
}

// MARK: - Helpers

@MainActor
private func makeTestPlaylistService() -> PlaylistService {
    PlaylistService(
        fetcher: StubPlaylistFetcher(),
        interval: 60,
        cacheCoordinator: CacheCoordinator(cache: InMemoryCache())
    )
}

// MARK: - Mock Types

@MainActor
final class MockWidgetRelevanceUpdater: WidgetRelevanceUpdating {
    private(set) var recordedCalls: [[RelevantIntent]] = []

    var callCount: Int { recordedCalls.count }
    var lastCall: [RelevantIntent]? { recordedCalls.last }

    func updateRelevantIntents(_ intents: sending [RelevantIntent]) async {
        recordedCalls.append(Array(intents))
    }

    /// Yields the main actor until at least `count` calls have been recorded.
    func waitForCallCount(_ count: Int) async {
        while recordedCalls.count < count {
            await Task.yield()
        }
    }
}

private struct StubPlaylistFetcher: PlaylistFetcherProtocol {
    func fetchPlaylist() async -> Playlist { .empty }
}

private final class InMemoryCache: Cache, @unchecked Sendable {
    private var dataStorage: [String: Data] = [:]
    private var metadataStorage: [String: CacheMetadata] = [:]

    func metadata(for key: String) -> CacheMetadata? { metadataStorage[key] }
    func data(for key: String) -> Data? { dataStorage[key] }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        if let data {
            dataStorage[key] = data
            metadataStorage[key] = metadata
        } else {
            remove(for: key)
        }
    }

    func remove(for key: String) {
        dataStorage.removeValue(forKey: key)
        metadataStorage.removeValue(forKey: key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        metadataStorage.map { ($0.key, $0.value) }
    }

    func clearAll() {
        dataStorage.removeAll()
        metadataStorage.removeAll()
    }

    func totalSize() -> Int64 {
        dataStorage.values.reduce(0) { $0 + Int64($1.count) }
    }
}

@Observable
@MainActor
final class MockPlaybackController: PlaybackController {
    var state: PlaybackState = .idle
    var isPlaying: Bool { state.isPlaying }
    var isLoading: Bool { state.isLoading }

    func play(reason: String) throws {}
    func toggle(reason: String) throws {}
    func stop() {}

    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { _ in }
    }

    func installRenderTap() {}
    func removeRenderTap() {}

    #if os(iOS)
    func handleAppDidEnterBackground() {}
    func handleAppWillEnterForeground() {}
    #endif
}
#endif
