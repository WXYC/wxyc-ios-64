//
//  PlaycutMetadataServiceCoalescingTests.swift
//  Metadata
//
//  Tests for in-flight request coalescing in PlaycutMetadataService (#282):
//  concurrent callers asking for the same (artist, release, track) tuple
//  while the cache is cold must share one underlying `/proxy/metadata/album`
//  fetch, callers asking for different tuples must not, one caller's
//  cancellation must not affect another observer, and the coalescing window
//  must be the in-flight duration only.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//
//  Declared as an extension of `PlaycutMetadataServiceHTTPTests` rather than
//  as a suite of its own — `CoreTesting.QueuedStubURLProtocol` registers by
//  class, so its header doc allows at most one adopting suite per test
//  bundle and directs further adopters to extend the existing one. See
//  `PlaycutMetadataResolverTests.swift` for the same arrangement.
//

import Testing
import Foundation
import Core
import CachingTesting
import CoreTesting
import Playlist
import PlaylistTesting
@testable import Caching
@testable import Metadata

extension PlaycutMetadataServiceHTTPTests {

    /// A `/proxy/metadata/album` body that omits `discogsArtistId`, so
    /// `fetchArtistMetadata` never fires and every captured request is
    /// attributable to the album fetch this file is testing.
    private static var albumBodyWithoutArtistId: Data {
        """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": 2024,
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
    }

    @Test("Concurrent calls for the same (artist, release, track) share exactly one underlying fetch")
    func concurrentCallsForSameKeyShareOneUnderlyingFetch() async throws {
        let mockURLSession = QueuedStubURLProtocol.makeSession()
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            urlSession: mockURLSession,
            cache: cache
        )
        QueuedStubURLProtocol.setBody(Self.albumBodyWithoutArtistId)

        let playcut = Playcut.stub(
            songTitle: "Crawl",
            labelName: "Houndstooth",
            artistName: "Djrum",
            releaseTitle: "Meaning's Edge"
        )

        // When — two concurrent callers ask for the exact same playcut while
        // the cache is cold.
        async let first = service.fetchMetadata(for: playcut)
        async let second = service.fetchMetadata(for: playcut)
        let (resultA, resultB) = await (first, second)

        // Then — both observe the same answer, from exactly one network call.
        #expect(resultA.album.releaseYear == 2024)
        #expect(resultB.album.releaseYear == 2024)
        #expect(QueuedStubURLProtocol.capturedRequests().count == 1, "Concurrent calls for the same key must share one underlying fetch")
    }

    @Test("Concurrent calls for different (artist, release, track) tuples issue independent fetches")
    func concurrentCallsForDifferentKeysAreIndependent() async throws {
        let mockURLSession = QueuedStubURLProtocol.makeSession()
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            urlSession: mockURLSession,
            cache: cache
        )
        QueuedStubURLProtocol.setBody(Self.albumBodyWithoutArtistId)

        let playcutA = Playcut.stub(
            songTitle: "Crawl",
            labelName: "Houndstooth",
            artistName: "Djrum",
            releaseTitle: "Meaning's Edge"
        )
        let playcutB = Playcut.stub(
            id: 2,
            songTitle: "Back, Baby",
            labelName: "Drag City",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again"
        )

        // When — two concurrent callers ask for genuinely different tuples.
        async let first = service.fetchMetadata(for: playcutA)
        async let second = service.fetchMetadata(for: playcutB)
        let (resultA, resultB) = await (first, second)

        // Then — each falls back to its own playcut's label (proving they
        // resolved independently, not from a shared/misattributed answer),
        // and each spent its own network call.
        #expect(resultA.album.label == "Houndstooth")
        #expect(resultB.album.label == "Drag City")
        #expect(QueuedStubURLProtocol.capturedRequests().count == 2, "Different keys must not be coalesced")
    }

    @Test("Two different songs on the same album are not coalesced, so each gets its own streaming answer")
    func differentTracksOnSameAlbumAreNotCoalesced() async throws {
        // The endpoint's streaming-link fields are resolved per track
        // (`trackTitle` is a query parameter precisely because streaming URLs
        // differ per song), so coalescing on artist+release alone would risk
        // handing one track's streaming links to a different track's cache
        // entry. This guards that the coalescing key is at least as specific
        // as the query itself.
        let mockURLSession = QueuedStubURLProtocol.makeSession()
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            urlSession: mockURLSession,
            cache: cache
        )
        QueuedStubURLProtocol.setBody(Self.albumBodyWithoutArtistId)

        let trackOne = Playcut.stub(
            songTitle: "Crawl",
            labelName: "Houndstooth",
            artistName: "Djrum",
            releaseTitle: "Meaning's Edge"
        )
        let trackTwo = Playcut.stub(
            id: 2,
            songTitle: "Fields",
            labelName: "Houndstooth",
            artistName: "Djrum",
            releaseTitle: "Meaning's Edge"
        )

        async let first = service.fetchMetadata(for: trackOne)
        async let second = service.fetchMetadata(for: trackTwo)
        _ = await (first, second)

        #expect(QueuedStubURLProtocol.capturedRequests().count == 2, "Different tracks on the same album must not share a coalesced fetch")

        let queries = QueuedStubURLProtocol.capturedRequests().compactMap {
            $0.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first(where: { $0.name == "trackTitle" })?.value
        }
        #expect(Set(queries) == ["Crawl", "Fields"])
    }

    @Test("One observer's cancellation does not fail another observer awaiting the same coalesced fetch")
    func cancellationOfOneObserverDoesNotFailAnother() async throws {
        let mockURLSession = QueuedStubURLProtocol.makeSession()
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            urlSession: mockURLSession,
            cache: cache
        )
        QueuedStubURLProtocol.setBody(Self.albumBodyWithoutArtistId)

        let playcut = Playcut.stub(
            songTitle: "Crawl",
            labelName: "Houndstooth",
            artistName: "Djrum",
            releaseTitle: "Meaning's Edge"
        )

        let observerA = Task { await service.fetchMetadata(for: playcut) }
        let observerB = Task { await service.fetchMetadata(for: playcut) }

        // Cancel the first observer immediately; the second must still
        // complete with the real answer, sharing the one underlying fetch.
        observerA.cancel()

        let resultB = await observerB.value
        #expect(resultB.album.releaseYear == 2024, "The uncancelled observer must still receive the fetched answer")
        #expect(QueuedStubURLProtocol.capturedRequests().count == 1, "The cancelled observer must not have caused a second, independent fetch")
    }

    @Test("The coalescing window is the in-flight duration only — a later call re-fetches rather than reusing a finished task")
    func laterCallAfterCompletionIssuesAFreshFetch() async throws {
        let mockURLSession = QueuedStubURLProtocol.makeSession()
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            urlSession: mockURLSession,
            cache: cache
        )

        let playcut = Playcut.stub(
            songTitle: "Crawl",
            labelName: "Houndstooth",
            artistName: "Djrum",
            releaseTitle: "Meaning's Edge"
        )

        // First call: every attempt 5xxs, so retries (#284) exhaust and
        // nothing is cached.
        QueuedStubURLProtocol.setResponse(statusCode: 503, body: Data(#"{"error": "Service Unavailable"}"#.utf8))
        let firstResult = await service.fetchMetadata(for: playcut)
        #expect(firstResult.album.label == "Houndstooth")
        let requestsAfterFirstCall = QueuedStubURLProtocol.capturedRequests().count
        #expect(requestsAfterFirstCall == 3, "The first call spends its own bounded retry budget")

        // Second call, issued only after the first fully completed: since
        // nothing was cached, this must be a genuinely fresh fetch — not a
        // reuse of the first call's now-finished (and never-cached) task.
        QueuedStubURLProtocol.setResponses([(200, Self.albumBodyWithoutArtistId)])
        let secondResult = await service.fetchMetadata(for: playcut)

        #expect(secondResult.album.releaseYear == 2024, "A later call must re-fetch rather than being stuck on the first call's failed task")
        #expect(QueuedStubURLProtocol.capturedRequests().count == 1, "setResponses resets the capture log; the second call must have issued a new request")
    }
}
