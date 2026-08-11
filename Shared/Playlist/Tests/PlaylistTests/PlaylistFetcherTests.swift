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
import PlaylistTesting
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

        // The reported context embeds the resolved version, so pin it rather
        // than inheriting `PlaylistAPIVersion.defaultVersion` — and build the
        // expectation from the same constant, so this asserts the *shape* of
        // the context string instead of re-pinning a version literal that has
        // to be chased every time the default moves.
        let apiVersion = PlaylistAPIVersion.v2
        let fetcher = PlaylistFetcher(
            apiVersion: apiVersion,
            dataSource: mockDataSource,
            errorReporter: mockErrorReporter,
            analytics: mockAnalytics
        )
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockDataSource.fetchCount == 1)
        #expect(mockErrorReporter.allReportedErrors.count == 1)
        #expect(mockErrorReporter.allReportedErrors.first?.context == "fetchPlaylist(API \(apiVersion.rawValue))")
    }

    @Test("fetchPlaylist returns empty playlist on URLError")
    func fetchPlaylistReturnsEmptyOnURLError() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockErrorReporter = MockErrorReporter()
        let mockAnalytics = MockStructuredAnalytics()
        mockDataSource.errorToThrow = URLError(.notConnectedToInternet)

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

    @Test("fetchPlaylist returns empty playlist on DecodingError")
    func fetchPlaylistReturnsEmptyOnDecodingError() async {
        let mockDataSource = MockPlaylistDataSource()
        let mockErrorReporter = MockErrorReporter()
        let mockAnalytics = MockStructuredAnalytics()
        mockDataSource.errorToThrow = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Test decoder error"))

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
        // Cancellation must neither be reported nor counted: no error report and
        // no phantom fetch_playlist_event in the success/failure denominator.
        #expect(mockErrorReporter.allReportedErrors.isEmpty)
        #expect(mockAnalytics.events(named: FetchPlaylistEvent.name).isEmpty)
    }

    // MARK: - fetchErrorCount (WXYC/wxyc-ios-64#267)
    //
    // `fetchPlaylist()` swallows every thrown error to `.empty` with no signal
    // in its return value, so a caller polling in a loop (`PlaylistService`)
    // cannot distinguish a genuinely empty playlist from a failed fetch.
    // `fetchErrorCount` is a cumulative, in-process counter of genuine
    // failures — observability only, does not change what `fetchPlaylist()`
    // returns.

    @Test("fetchErrorCount is cumulative across failures and unaffected by successes")
    func fetchErrorCountAccumulatesAcrossFailures() async {
        let mockDataSource = MockPlaylistDataSource()
        let fetcher = PlaylistFetcher(
            dataSource: mockDataSource,
            errorReporter: MockErrorReporter(),
            analytics: MockStructuredAnalytics()
        )

        #expect(fetcher.fetchErrorCount == 0)

        mockDataSource.errorToThrow = NSError(domain: "TestDomain", code: 500, userInfo: nil)
        _ = await fetcher.fetchPlaylist()
        #expect(fetcher.fetchErrorCount == 1)

        // A subsequent success must not move the counter.
        mockDataSource.errorToThrow = nil
        mockDataSource.playlistToReturn = .stub(playcuts: [
            .stub(songTitle: "la paradoja", artistName: "Juana Molina")
        ])
        _ = await fetcher.fetchPlaylist()
        #expect(fetcher.fetchErrorCount == 1)

        // A further failure increments again — cumulative, not "last outcome."
        mockDataSource.errorToThrow = URLError(.timedOut)
        _ = await fetcher.fetchPlaylist()
        #expect(fetcher.fetchErrorCount == 2)
    }

    @Test("cancellation does not increment fetchErrorCount")
    func fetchErrorCountIgnoresCancellation() async {
        let mockDataSource = MockPlaylistDataSource()
        mockDataSource.errorToThrow = CancellationError()
        let fetcher = PlaylistFetcher(
            dataSource: mockDataSource,
            errorReporter: MockErrorReporter(),
            analytics: MockStructuredAnalytics()
        )

        _ = await fetcher.fetchPlaylist()

        #expect(fetcher.fetchErrorCount == 0)
    }
}

// MARK: - PlaylistFetcher Analytics Tests (#414 / #415)

/// Verifies that every playlist fetch outcome (success, empty, failure) emits a
/// `fetch_playlist_event` tagged with the resolved API version, and that the
/// success-only 10% sampling now covers only the healthy, non-empty success
/// path — empty results and failures are always captured.
@Suite("PlaylistFetcher Analytics Tests", .serialized)
struct PlaylistFetcherAnalyticsTests {
    /// The properties of the single captured `fetch_playlist_event`, if any.
    private func fetchEventProperties(_ analytics: MockStructuredAnalytics) -> [String: Any]? {
        analytics.events(named: FetchPlaylistEvent.name).first?.properties
    }

    @Test(
        "emits a fetch_playlist_event on an empty (but successful) result, tagged with the API version",
        arguments: [PlaylistAPIVersion.v1, .v2]
    )
    func emitsEventOnEmptyResult(version: PlaylistAPIVersion) async {
        let dataSource = MockPlaylistDataSource() // returns .empty without throwing
        let analytics = MockStructuredAnalytics()
        let fetcher = PlaylistFetcher(
            apiVersion: version,
            dataSource: dataSource,
            errorReporter: MockErrorReporter(),
            analytics: analytics,
            // Gate closed: proves empty results are never sampled away.
            healthySuccessSampler: { false }
        )

        _ = await fetcher.fetchPlaylist()

        let props = fetchEventProperties(analytics)
        #expect(props?["api_version"] as? String == version.rawValue)
        #expect(props?["result_count"] as? Int == 0)
        #expect(props?["succeeded"] as? Bool == true)
    }

    @Test(
        "emits a fetch_playlist_event on failure, tagged with the API version",
        arguments: [PlaylistAPIVersion.v1, .v2]
    )
    func emitsEventOnFailure(version: PlaylistAPIVersion) async {
        let dataSource = MockPlaylistDataSource()
        dataSource.errorToThrow = NSError(domain: "TestDomain", code: 123, userInfo: nil)
        let analytics = MockStructuredAnalytics()
        let reporter = MockErrorReporter()
        let fetcher = PlaylistFetcher(
            apiVersion: version,
            dataSource: dataSource,
            errorReporter: reporter,
            analytics: analytics,
            // Gate closed: proves failures are never sampled away.
            healthySuccessSampler: { false }
        )

        _ = await fetcher.fetchPlaylist()

        let props = fetchEventProperties(analytics)
        #expect(props?["api_version"] as? String == version.rawValue)
        #expect(props?["result_count"] as? Int == 0)
        #expect(props?["succeeded"] as? Bool == false)

        // #414: the version also rides the error report as a structured property,
        // not just inside the free-text context string.
        #expect(reporter.allReportedErrors.first?.additionalData["api_version"] == version.rawValue)
    }

    @Test(
        "emits a non-empty success event carrying the result count when the sample gate is open",
        arguments: [PlaylistAPIVersion.v1, .v2]
    )
    func emitsNonEmptySuccessWhenSampled(version: PlaylistAPIVersion) async {
        let playlist = Playlist.stub(playcuts: [
            .stub(id: 1, songTitle: "la paradoja", artistName: "Juana Molina"),
            .stub(id: 2, songTitle: "Back, Baby", artistName: "Jessica Pratt"),
        ])
        let dataSource = MockPlaylistDataSource()
        dataSource.playlistToReturn = playlist
        let analytics = MockStructuredAnalytics()
        let fetcher = PlaylistFetcher(
            apiVersion: version,
            dataSource: dataSource,
            errorReporter: MockErrorReporter(),
            analytics: analytics,
            healthySuccessSampler: { true }
        )

        _ = await fetcher.fetchPlaylist()

        let props = fetchEventProperties(analytics)
        #expect(props?["api_version"] as? String == version.rawValue)
        #expect(props?["succeeded"] as? Bool == true)
        #expect(props?["result_count"] as? Int == playlist.entries.count)
    }

    @Test("suppresses the non-empty success event when the sample gate is closed")
    func suppressesNonEmptySuccessWhenGateClosed() async {
        let dataSource = MockPlaylistDataSource()
        dataSource.playlistToReturn = Playlist.stub(playcuts: [
            .stub(id: 1, songTitle: "la paradoja", artistName: "Juana Molina"),
        ])
        let analytics = MockStructuredAnalytics()
        let fetcher = PlaylistFetcher(
            apiVersion: .v1,
            dataSource: dataSource,
            errorReporter: MockErrorReporter(),
            analytics: analytics,
            healthySuccessSampler: { false }
        )

        _ = await fetcher.fetchPlaylist()

        #expect(analytics.events(named: FetchPlaylistEvent.name).isEmpty)
    }

    @Test("a URLSession cancellation (URLError.cancelled) is neither reported nor counted, even when the task flag is unset")
    func urlSessionCancellationIsNotAPhantomFailure() async {
        // `URLSession.data(for:)` throws `URLError(.cancelled)` — NOT Swift's
        // `CancellationError` — when a fetch is torn down (e.g. switchAPIVersion
        // swapping the data source). This can surface without the surrounding
        // task's `isCancelled` flag being set, so it must be classified from the
        // error itself, not from `Task.isCancelled`.
        let dataSource = MockPlaylistDataSource()
        dataSource.errorToThrow = URLError(.cancelled)
        let analytics = MockStructuredAnalytics()
        let reporter = MockErrorReporter()
        let fetcher = PlaylistFetcher(
            apiVersion: .v2,
            dataSource: dataSource,
            errorReporter: reporter,
            analytics: analytics,
            healthySuccessSampler: { true }
        )

        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(reporter.allReportedErrors.isEmpty)
        #expect(analytics.events(named: FetchPlaylistEvent.name).isEmpty)
    }

    @Test("cancelling an in-flight fetch task emits no event and reports nothing")
    func realTaskCancellationOfInFlightFetchIsSilent() async {
        let dataSource = HangingPlaylistDataSource()
        let analytics = MockStructuredAnalytics()
        let reporter = MockErrorReporter()
        let fetcher = PlaylistFetcher(
            apiVersion: .v2,
            dataSource: dataSource,
            errorReporter: reporter,
            analytics: analytics,
            healthySuccessSampler: { true }
        )

        let task = Task { await fetcher.fetchPlaylist() }
        // Wait until the fetch is genuinely in-flight so the cancel can't race
        // ahead of the network call starting.
        while await dataSource.hasStarted == false {
            await Task.yield()
        }
        task.cancel()
        let result = await task.value

        #expect(result == .empty)
        #expect(reporter.allReportedErrors.isEmpty)
        #expect(analytics.events(named: FetchPlaylistEvent.name).isEmpty)
    }
}

// MARK: - Test Doubles

/// A data source that suspends until its surrounding task is cancelled, then
/// throws the way `URLSession.data(for:)` does — `URLError(.cancelled)`, not
/// Swift's `CancellationError`. `hasStarted` lets a test await the in-flight
/// state before cancelling. An actor gives data-race-free access to the flag.
private actor HangingPlaylistDataSource: PlaylistDataSource {
    private(set) var hasStarted = false

    func getPlaylist() async throws -> Playlist {
        hasStarted = true
        while !Task.isCancelled {
            await Task.yield()
        }
        throw URLError(.cancelled)
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

