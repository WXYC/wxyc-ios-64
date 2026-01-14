//
//  PlaylistFetcherTests.swift
//  Playlist
//
//  Tests for PlaylistFetcher data retrieval.
//
//  Created by Jake Bromberg on 12/08/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
import Analytics
@testable import Playlist

// MARK: - Mock PlaylistDataSource

final class MockPlaylistDataSource: PlaylistDataSource, @unchecked Sendable {
    var playlistToReturn: Playlist = .empty
    var errorToThrow: Error?
    var fetchCount = 0

    func getPlaylist() async throws -> Playlist {
        fetchCount += 1

        if let error = errorToThrow {
            throw error
        }

        return playlistToReturn
    }
}

// MARK: - Mock PlaylistAnalytics

final class MockPlaylistAnalytics: PlaylistAnalytics {
    var capturedEvents: [(event: String, context: String?, additionalData: [String: String])] = []
    var capturedErrors: [(context: String, additionalData: [String: String])] = []

    func capture(_ event: String, context: String?, additionalData: [String: String]) {
        capturedEvents.append((event, context, additionalData))
    }

    func capture(error: String, code: Int, context: String, additionalData: [String: String]) {
        capturedErrors.append((context, additionalData))
    }

    func capture(error: AnalyticsOSError, context: String, additionalData: [String: String]) {
        capturedErrors.append((context, additionalData))
    }

    func capture(error: AnalyticsDecoderError, context: String, additionalData: [String: String]) {
        capturedErrors.append((context, additionalData))
    }
}

// MARK: - PlaylistFetcher Tests

@Suite("PlaylistFetcher Tests")
struct PlaylistFetcherTests {
    @Test("fetchPlaylist returns playlist on success")
    func fetchPlaylistReturnsPlaylistOnSuccess() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockAnalytics = MockPlaylistAnalytics()
        let expectedPlaylist = Playlist(
            playcuts: [
                Playcut(
                    id: 1,
                    hour: 1000,
                    chronOrderID: 1,
                    songTitle: "Test Song",
                    labelName: "Test Label",
                    artistName: "Test Artist",
                    releaseTitle: "Test Album"
                )
            ],
            breakpoints: [],
            talksets: []
        )
        mockDataSource.playlistToReturn = expectedPlaylist

        let fetcher = PlaylistFetcher(dataSource: mockDataSource, analytics: mockAnalytics)
        let result = await fetcher.fetchPlaylist()

        #expect(result == expectedPlaylist)
        #expect(mockDataSource.fetchCount == 1)
    }

    @Test("fetchPlaylist returns empty playlist on NSError")
    func fetchPlaylistReturnsEmptyOnNSError() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockAnalytics = MockPlaylistAnalytics()
        mockDataSource.errorToThrow = NSError(domain: "TestDomain", code: 123, userInfo: nil)

        let fetcher = PlaylistFetcher(dataSource: mockDataSource, analytics: mockAnalytics)
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockDataSource.fetchCount == 1)
        #expect(mockAnalytics.capturedErrors.count == 1)
    }

    @Test("fetchPlaylist returns empty playlist on AnalyticsOSError")
    func fetchPlaylistReturnsEmptyOnAnalyticsOSError() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockAnalytics = MockPlaylistAnalytics()
        mockDataSource.errorToThrow = AnalyticsOSError(domain: "TestDomain", code: 123, description: "Test error")

        let fetcher = PlaylistFetcher(dataSource: mockDataSource, analytics: mockAnalytics)
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockDataSource.fetchCount == 1)
        #expect(mockAnalytics.capturedErrors.count == 1)
    }

    @Test("fetchPlaylist returns empty playlist on AnalyticsDecoderError")
    func fetchPlaylistReturnsEmptyOnAnalyticsDecoderError() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockAnalytics = MockPlaylistAnalytics()
        mockDataSource.errorToThrow = AnalyticsDecoderError(description: "Test decoder error")

        let fetcher = PlaylistFetcher(dataSource: mockDataSource, analytics: mockAnalytics)
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockDataSource.fetchCount == 1)
        #expect(mockAnalytics.capturedErrors.count == 1)
    }

    @Test("fetchPlaylist returns empty playlist on CancellationError")
    func fetchPlaylistReturnsEmptyOnCancellationError() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockAnalytics = MockPlaylistAnalytics()
        mockDataSource.errorToThrow = CancellationError()

        let fetcher = PlaylistFetcher(dataSource: mockDataSource, analytics: mockAnalytics)
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockDataSource.fetchCount == 1)
        // CancellationError should not trigger analytics
        #expect(mockAnalytics.capturedErrors.isEmpty)
    }
}
