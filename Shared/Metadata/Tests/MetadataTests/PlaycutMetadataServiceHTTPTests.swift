//
//  PlaycutMetadataServiceHTTPTests.swift
//  Metadata
//
//  Tests for HTTP status code validation in PlaycutMetadataService.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import os
import Core
import CoreTesting
import Playlist
import PlaylistTesting
@testable import Caching
@testable import Metadata

// MARK: - HTTP Status Code Validation Tests

@Suite("PlaycutMetadataService HTTP Status Validation", .serialized)
struct PlaycutMetadataServiceHTTPTests {

    @Test("Falls back to flowsheet metadata when the proxy returns 502 Bad Gateway")
    func fallsBackOnBadGateway() async throws {
        // Given
        let mockURLSession = QueuedStubURLProtocol.makeSession()

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "test-token"),
            urlSession: mockURLSession,
            cache: cache
        )

        // Configure mock to return 502
        QueuedStubURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 502,
                httpVersion: nil,
                headerFields: nil
            )!
            let errorBody = #"{"error": "Bad Gateway"}"#.data(using: .utf8)!
            return (errorBody, response)
        }

        let playcut = Playcut.stub(
            songTitle: "VI Scose Poise",
            labelName: "Warp",
            artistName: "Autechre",
            releaseTitle: "Confield"
        )

        // When - fetchMetadata catches errors internally, so we verify
        // it returns empty/fallback metadata rather than garbage-decoded data
        let result = await service.fetchMetadata(for: playcut)

        // Then - album metadata should fall back to playcut's label,
        // not contain data decoded from the error body
        #expect(result.album.label == "Warp", "Should fall back to playcut label on HTTP error")
        #expect(result.album.releaseYear == nil, "Should not have decoded metadata from error body")
        #expect(result.album.discogsURL == nil, "Should not have decoded metadata from error body")
        #expect(result.streaming == .empty, "Should have empty streaming links on HTTP error")
    }

    @Test("Falls back to flowsheet metadata when the proxy returns 404 Not Found")
    func fallsBackOnNotFound() async throws {
        // Given
        let mockURLSession = QueuedStubURLProtocol.makeSession()

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "test-token"),
            urlSession: mockURLSession,
            cache: cache
        )

        // Configure mock to return 404
        QueuedStubURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            let errorBody = #"{"error": "Not Found"}"#.data(using: .utf8)!
            return (errorBody, response)
        }

        let playcut = Playcut.stub(
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA"
        )

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then
        #expect(result.album.label == "Sonamos", "Should fall back to playcut label on 404")
        #expect(result.streaming == .empty, "Should have empty streaming links on 404")
    }

    @Test("Succeeds when proxy returns 200 OK")
    func succeedsOn200() async throws {
        // Given
        let mockURLSession = QueuedStubURLProtocol.makeSession()

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "test-token"),
            urlSession: mockURLSession,
            cache: cache
        )

        // Configure mock to return 200 with valid metadata
        QueuedStubURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
            {
                "discogsReleaseId": 12345,
                "discogsArtistId": 67890,
                "discogsUrl": "https://www.discogs.com/release/12345",
                "releaseYear": 2001,
                "label": "Warp Records",
                "genres": ["Electronic"],
                "styles": ["IDM"],
                "spotifyUrl": null,
                "appleMusicUrl": null,
                "youtubeMusicUrl": null,
                "bandcampUrl": null,
                "soundcloudUrl": null
            }
            """.data(using: .utf8)!
            return (body, response)
        }

        let playcut = Playcut.stub(
            songTitle: "VI Scose Poise",
            labelName: "Warp",
            artistName: "Autechre",
            releaseTitle: "Confield"
        )

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then
        #expect(result.album.label == "Warp Records", "Should decode metadata from 200 response")
        #expect(result.album.releaseYear == 2001)
        #expect(result.album.genres == ["Electronic"])
    }

    @Test("Decodes criticReviews[] from a 200 response into domain review items")
    func decodesCriticReviews() async throws {
        // Given
        let mockURLSession = QueuedStubURLProtocol.makeSession()

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "test-token"),
            urlSession: mockURLSession,
            cache: cache
        )

        // Response carries two reviews: one fully populated, one with only the
        // required fields, plus one with a malformed URL that must be dropped.
        QueuedStubURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
            {
                "discogsReleaseId": 12345,
                "label": "Sonamos",
                "criticReviews": [
                    {
                        "source": "The Quietus",
                        "url": "https://thequietus.com/articles/juana-molina-doga",
                        "snippet": "DOGA folds field recordings into looped songcraft.",
                        "author": "Jane Critic",
                        "publishedDate": "2024-03-15",
                        "rating": "8.0"
                    },
                    {
                        "source": "The Quietus",
                        "url": "https://thequietus.com/articles/second",
                        "snippet": "Required-fields-only card."
                    },
                    {
                        "source": "Broken",
                        "url": "   ",
                        "snippet": "Should be dropped for a blank link-out URL."
                    }
                ],
                "spotifyUrl": null,
                "appleMusicUrl": null,
                "youtubeMusicUrl": null,
                "bandcampUrl": null,
                "soundcloudUrl": null
            }
            """.data(using: .utf8)!
            return (body, response)
        }

        let playcut = Playcut.stub(
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA"
        )

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then — the malformed-URL review is dropped, both valid ones survive.
        let reviews = try #require(result.album.criticReviews)
        #expect(reviews.count == 2)
        #expect(result.album.hasCriticReviews == true)

        let first = reviews[0]
        #expect(first.source == "The Quietus")
        #expect(first.url.absoluteString == "https://thequietus.com/articles/juana-molina-doga")
        #expect(first.snippet == "DOGA folds field recordings into looped songcraft.")
        #expect(first.author == "Jane Critic")
        #expect(first.publishedDate == "2024-03-15")
        #expect(first.rating == "8.0")

        let second = reviews[1]
        #expect(second.author == nil)
        #expect(second.publishedDate == nil)
        #expect(second.rating == nil)
    }

    @Test("Omits criticReviews when the response has no such field")
    func omitsCriticReviewsWhenAbsent() async throws {
        // Given
        let mockURLSession = QueuedStubURLProtocol.makeSession()

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "test-token"),
            urlSession: mockURLSession,
            cache: cache
        )

        QueuedStubURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
            {
                "label": "Sonamos",
                "spotifyUrl": null,
                "appleMusicUrl": null,
                "youtubeMusicUrl": null,
                "bandcampUrl": null,
                "soundcloudUrl": null
            }
            """.data(using: .utf8)!
            return (body, response)
        }

        let playcut = Playcut.stub(
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA"
        )

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then — an un-seeded album has no reviews attached, section stays hidden.
        #expect(result.album.criticReviews == nil)
        #expect(result.album.hasCriticReviews == false)
    }

    @Test("Includes Authorization header when token provider is present")
    func includesAuthorizationHeader() async throws {
        // Given
        let mockURLSession = QueuedStubURLProtocol.makeSession()

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "my-secret-token"),
            urlSession: mockURLSession,
            cache: cache
        )

        QueuedStubURLProtocol.setBody(Data("""
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.utf8))

        let playcut = Playcut.stub(
            songTitle: "Back, Baby",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again"
        )

        // When
        _ = await service.fetchMetadata(for: playcut)

        // Then
        let capturedRequest = QueuedStubURLProtocol.capturedRequest()
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer my-secret-token")
    }

    @Test("Reauthenticates once and retries when the proxy returns 401")
    func retriesOnceOn401ThenSucceeds() async throws {
        // Given
        let mockURLSession = QueuedStubURLProtocol.makeSession()

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "stale-token", refreshedToken: "fresh-token"),
            urlSession: mockURLSession,
            cache: cache
        )

        // First request 401s (rejected cached token); the retried request,
        // carrying the reauthenticated token, gets a 200 with real metadata.
        QueuedStubURLProtocol.setResponses([
            (401, Data(#"{"error": "Unauthorized"}"#.utf8)),
            (200, Data("""
            {
                "discogsReleaseId": 12345,
                "label": "Warp Records",
                "releaseYear": 2001,
                "spotifyUrl": null,
                "appleMusicUrl": null,
                "youtubeMusicUrl": null,
                "bandcampUrl": null,
                "soundcloudUrl": null
            }
            """.utf8)),
        ])

        let playcut = Playcut.stub(
            songTitle: "VI Scose Poise",
            labelName: "Warp",
            artistName: "Autechre",
            releaseTitle: "Confield"
        )

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then — the retry's 200 response is what the service returns, and
        // it carried the reauthenticated token, not the rejected one.
        #expect(result.album.label == "Warp Records")
        #expect(result.album.releaseYear == 2001)
        let capturedAuthorizationHeaders = QueuedStubURLProtocol.capturedRequests()
            .map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(capturedAuthorizationHeaders.count == 2)
        #expect(capturedAuthorizationHeaders[0] == "Bearer stale-token")
        #expect(capturedAuthorizationHeaders[1] == "Bearer fresh-token")
    }

    // MARK: - Transient-vs-permanent classification (#284)

    @Test("Retries a transient 503 with backoff, then succeeds")
    func retriesTransientServerErrorThenSucceeds() async throws {
        // Given — the first two attempts hit a transient 5xx; the third
        // (bounded — #284 caps this service at 3 total attempts) succeeds.
        let mockURLSession = QueuedStubURLProtocol.makeSession()
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            urlSession: mockURLSession,
            cache: cache
        )

        QueuedStubURLProtocol.setResponses([
            (503, Data(#"{"error": "Service Unavailable"}"#.utf8)),
            (503, Data(#"{"error": "Service Unavailable"}"#.utf8)),
            (200, Data("""
            {
                "discogsReleaseId": 12345,
                "label": "Warp Records",
                "releaseYear": 2001,
                "spotifyUrl": null,
                "appleMusicUrl": null,
                "youtubeMusicUrl": null,
                "bandcampUrl": null,
                "soundcloudUrl": null
            }
            """.utf8)),
        ])

        let playcut = Playcut.stub(
            songTitle: "VI Scose Poise",
            labelName: "Warp",
            artistName: "Autechre",
            releaseTitle: "Confield"
        )

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then — the third attempt's answer wins, and all three were spent.
        #expect(result.album.label == "Warp Records")
        #expect(result.album.releaseYear == 2001)
        #expect(QueuedStubURLProtocol.capturedRequests().count == 3)
    }

    @Test("Retries a transient networking blip (URLError) with backoff, then succeeds")
    func retriesTransientNetworkErrorThenSucceeds() async throws {
        // Given — a handler that throws a transient URLError twice, then serves 200.
        let attemptCount = OSAllocatedUnfairLock(initialState: 0)
        let mockURLSession = QueuedStubURLProtocol.session { request in
            let attempt = attemptCount.withLock { count -> Int in
                count += 1
                return count
            }
            if attempt < 3 {
                throw URLError(.networkConnectionLost)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = Data("""
            {
                "discogsReleaseId": 54321,
                "label": "Drag City Records",
                "releaseYear": 2015,
                "spotifyUrl": null,
                "appleMusicUrl": null,
                "youtubeMusicUrl": null,
                "bandcampUrl": null,
                "soundcloudUrl": null
            }
            """.utf8)
            return (body, response)
        }

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            urlSession: mockURLSession,
            cache: cache
        )

        let playcut = Playcut.stub(
            songTitle: "Back, Baby",
            labelName: "Drag City",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again"
        )

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then
        #expect(result.album.label == "Drag City Records")
        #expect(attemptCount.withLock { $0 } == 3)
    }

    @Test("Gives up after exhausting retries on a persistent transient error, without poisoning the cache")
    func givesUpAfterExhaustingRetriesOnPersistentTransientError() async throws {
        // Given — every attempt 5xxs.
        let mockURLSession = QueuedStubURLProtocol.makeSession()
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            urlSession: mockURLSession,
            cache: cache
        )

        QueuedStubURLProtocol.setResponse(statusCode: 503, body: Data(#"{"error": "Service Unavailable"}"#.utf8))

        let playcut = Playcut.stub(
            songTitle: "VI Scose Poise",
            labelName: "Warp",
            artistName: "Autechre",
            releaseTitle: "Confield"
        )

        // When
        let timer = Core.Timer.start()
        let result = await service.fetchMetadata(for: playcut)
        let elapsed = timer.duration()

        // Then — falls back to the flowsheet label, spends exactly the bounded
        // number of attempts, stays under the ≤3s aggregate retry budget, and
        // never writes a negative cache entry for a condition that might clear
        // on the very next poll.
        #expect(result.album.label == "Warp", "Should fall back to playcut label once retries are exhausted")
        #expect(QueuedStubURLProtocol.capturedRequests().count == 3, "Bounded to 3 total attempts")
        #expect(elapsed < 3.0, "Total retry budget must stay under the ~3s UI-tap latency budget")
        #expect(mockCache.setKeys.isEmpty, "A persistently-transient failure must not poison the negative cache")
    }

    @Test("A 404 stores a negative cache entry immediately, without retrying")
    func permanentNotFoundCachesNegativeEntryImmediatelyWithoutRetrying() async throws {
        // Given
        let mockURLSession = QueuedStubURLProtocol.makeSession()
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            urlSession: mockURLSession,
            cache: cache
        )

        QueuedStubURLProtocol.setResponse(statusCode: 404, body: Data(#"{"error": "Not Found"}"#.utf8))

        // Not mid-enrichment, so the existing isSparse/midEnrichment TTL gate
        // (#812) puts this negative entry on the long TTL — a 404 is exactly
        // as durable an answer as a permanently-unmatched free-text play.
        let playcut = Playcut.stub(
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            metadataStatus: nil
        )

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then — a single attempt (permanent failures are not retried), and
        // the negative answer is cached immediately rather than left unwritten.
        #expect(result.album.label == "Sonamos")
        #expect(QueuedStubURLProtocol.capturedRequests().count == 1, "A 404 must not be retried")

        let albumKey = MetadataCacheKey.album(artistName: "Juana Molina", releaseTitle: "DOGA")
        #expect(mockCache.setKeys.contains(albumKey), "A 404 should store a negative album cache entry immediately")
        #expect(mockCache.metadata(for: albumKey)?.lifespan == .sevenDays)
    }

    @Test("A 401 is neither retried nor recorded as a negative answer")
    func authFailureIsNeitherRetriedNorNegativeCached() async throws {
        // #284's permanent bucket is a definitive absence — a 404 — and
        // nothing else. A 401 that outlived `authedData`'s
        // reauthenticate-and-retry is not Backend saying "no such album"; the
        // same goes for a 400 or a decode failure on a malformed payload.
        // Folding them in would pin a label-only record on the seven-day album
        // TTL, so a single auth outage would blank a week of cards — the exact
        // negative-cache poisoning this ticket exists to remove. They keep the
        // pre-#284 behavior instead: fall back, cache nothing, re-attempt on
        // the next card open.
        let mockURLSession = QueuedStubURLProtocol.makeSession()
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            urlSession: mockURLSession,
            cache: cache
        )

        QueuedStubURLProtocol.setResponse(statusCode: 401, body: Data(#"{"error": "Unauthorized"}"#.utf8))

        let playcut = Playcut.stub(
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            metadataStatus: nil
        )

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then
        #expect(result.album.label == "Sonamos", "Falls back to the flowsheet label")
        #expect(QueuedStubURLProtocol.capturedRequests().count == 1, "A 401 is not transient, so it is not retried")
        #expect(mockCache.setKeys.isEmpty, "An auth failure must not be recorded as 'this album does not exist'")
    }
}
