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
        let mockWebSession = MetadataMockWebSession()

        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "test-token"),
            session: mockWebSession,
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
        let mockWebSession = MetadataMockWebSession()

        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "test-token"),
            session: mockWebSession,
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
        let mockWebSession = MetadataMockWebSession()

        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "test-token"),
            session: mockWebSession,
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
        let mockWebSession = MetadataMockWebSession()

        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "test-token"),
            session: mockWebSession,
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
        let mockWebSession = MetadataMockWebSession()

        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "test-token"),
            session: mockWebSession,
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
        let mockWebSession = MetadataMockWebSession()

        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "my-secret-token"),
            session: mockWebSession,
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
        let mockWebSession = MetadataMockWebSession()

        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: RecordingTokenProvider(initialToken: "stale-token", refreshedToken: "fresh-token"),
            session: mockWebSession,
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
}
