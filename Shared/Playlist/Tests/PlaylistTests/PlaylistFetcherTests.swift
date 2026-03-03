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
import AnalyticsTesting
import Logger
import LoggerTesting
@testable import Playlist

// MARK: - PlaylistFetcher Tests

@Suite("PlaylistFetcher Tests", .serialized)
struct PlaylistFetcherTests {
    @Test("fetchPlaylist returns playlist on success")
    func fetchPlaylistReturnsPlaylistOnSuccess() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockErrorReporter = MockErrorReporter()
        let mockAnalytics = MockStructuredAnalytics()
        let expectedPlaylist = Playlist.stub(playcuts: [
            .stub(songTitle: "Test Song", labelName: "Test Label", artistName: "Test Artist")
        ])
        mockDataSource.playlistToReturn = expectedPlaylist

        let fetcher = PlaylistFetcher(
            dataSource: mockDataSource,
            errorReporter: mockErrorReporter,
            analytics: mockAnalytics
        )
        let result = await fetcher.fetchPlaylist()

        #expect(result == expectedPlaylist)
        #expect(mockDataSource.fetchCount == 1)
    }

    @Test("fetchPlaylist returns empty playlist on error")
    func fetchPlaylistReturnsEmptyOnError() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockErrorReporter = MockErrorReporter()
        let mockAnalytics = MockStructuredAnalytics()
        mockDataSource.errorToThrow = NSError(domain: "TestDomain", code: 123, userInfo: nil)

        let fetcher = PlaylistFetcher(
            dataSource: mockDataSource,
            errorReporter: mockErrorReporter,
            analytics: mockAnalytics
        )
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockDataSource.fetchCount == 1)
        #expect(mockErrorReporter.allReportedErrors.count == 1)
        #expect(mockErrorReporter.allReportedErrors.first?.context == "fetchPlaylist")
    }

    @Test("fetchPlaylist returns empty playlist on decoding error")
    func fetchPlaylistReturnsEmptyOnDecodingError() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockErrorReporter = MockErrorReporter()
        let mockAnalytics = MockStructuredAnalytics()
        mockDataSource.errorToThrow = AnalyticsOSError(domain: "TestDomain", code: 123, description: "Test error")

        let fetcher = PlaylistFetcher(
            dataSource: mockDataSource,
            errorReporter: mockErrorReporter,
            analytics: mockAnalytics
        )
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockDataSource.fetchCount == 1)
        #expect(mockErrorReporter.allReportedErrors.count == 1)
    }

    @Test("fetchPlaylist returns empty playlist on AnalyticsDecoderError")
    func fetchPlaylistReturnsEmptyOnAnalyticsDecoderError() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockErrorReporter = MockErrorReporter()
        let mockAnalytics = MockStructuredAnalytics()
        mockDataSource.errorToThrow = AnalyticsDecoderError(description: "Test decoder error")

        let fetcher = PlaylistFetcher(
            dataSource: mockDataSource,
            errorReporter: mockErrorReporter,
            analytics: mockAnalytics
        )
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockDataSource.fetchCount == 1)
        #expect(mockErrorReporter.allReportedErrors.count == 1)
    }

    @Test("fetchPlaylist returns empty playlist on CancellationError")
    func fetchPlaylistReturnsEmptyOnCancellationError() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockErrorReporter = MockErrorReporter()
        let mockAnalytics = MockStructuredAnalytics()
        mockDataSource.errorToThrow = CancellationError()

        let fetcher = PlaylistFetcher(
            dataSource: mockDataSource,
            errorReporter: mockErrorReporter,
            analytics: mockAnalytics
        )
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockDataSource.fetchCount == 1)
        // CancellationError should not trigger error reporting
        #expect(mockErrorReporter.allReportedErrors.isEmpty)
    }
}

// MARK: - Mojibake Repair Tests

@Suite("Data Mojibake Repair Tests")
struct DataMojibakeRepairTests {
    @Test("repairs UTF-8 mojibake in JSON data")
    func repairsMojibakeInJSON() {
        // "Bjork" encoded as UTF-8, then incorrectly decoded as Latin-1, then re-encoded as UTF-8
        // Results in "BjÃ¶rk" in the JSON
        let corruptedJSON = """
        {"artistName":"BjÃ¶rk","songTitle":"Venus as a Boy"}
        """
        let corruptedData = corruptedJSON.data(using: .utf8)!

        let repairedData = corruptedData.repairingMojibake()
        let repairedString = String(data: repairedData, encoding: .utf8)!

        #expect(repairedString.contains("Björk"))
        #expect(!repairedString.contains("BjÃ¶rk"))
    }

    @Test("preserves ASCII-only data unchanged")
    func preservesASCIIData() {
        let asciiJSON = """
        {"artistName":"The Beatles","songTitle":"Yesterday"}
        """
        let asciiData = asciiJSON.data(using: .utf8)!

        let repairedData = asciiData.repairingMojibake()

        #expect(repairedData == asciiData)
    }

    @Test("repairs multiple mojibake characters")
    func repairsMultipleMojibakeCharacters() {
        // Create proper mojibake by encoding UTF-8 string, then interpreting bytes as Latin-1
        let original = """
        {"artistName":"Sigur Rós","albumTitle":"Ágætis byrjun"}
        """
        // Simulate server bug: UTF-8 bytes interpreted as Latin-1, then served as UTF-8
        let utf8Bytes = Array(original.utf8)
        let mojibakeString = String(bytes: utf8Bytes, encoding: .isoLatin1)!
        let corruptedData = mojibakeString.data(using: .utf8)!

        let repairedData = corruptedData.repairingMojibake()
        let repairedString = String(data: repairedData, encoding: .utf8)!

        #expect(repairedString.contains("Sigur Rós"))
        #expect(repairedString.contains("Ágætis byrjun"))
    }
}

// MARK: - Test Doubles

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
