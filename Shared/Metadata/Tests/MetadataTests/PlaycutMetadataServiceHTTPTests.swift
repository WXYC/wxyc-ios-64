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
import Playlist
@testable import Caching
@testable import Metadata

// MARK: - Mock URLProtocol

/// A URLProtocol subclass that returns configurable responses for testing.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseHandler: ((URLRequest) -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.responseHandler,
              let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let (data, response) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Mock Token Provider

struct MockTokenProvider: SessionTokenProvider {
    let tokenValue: String

    func token() async throws -> String {
        tokenValue
    }
}

// MARK: - HTTP Status Code Validation Tests

@Suite("PlaycutMetadataService HTTP Status Validation", .serialized)
struct PlaycutMetadataServiceHTTPTests {

    @Test("Throws httpError when proxy returns 502 Bad Gateway")
    func throwsOnBadGateway() async throws {
        // Given
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockURLSession = URLSession(configuration: config)

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockWebSession = MetadataMockWebSession()

        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: MockTokenProvider(tokenValue: "test-token"),
            session: mockWebSession,
            urlSession: mockURLSession,
            cache: cache
        )

        // Configure mock to return 502
        MockURLProtocol.responseHandler = { request in
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

    @Test("Throws httpError when proxy returns 404 Not Found")
    func throwsOnNotFound() async throws {
        // Given
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockURLSession = URLSession(configuration: config)

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockWebSession = MetadataMockWebSession()

        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: MockTokenProvider(tokenValue: "test-token"),
            session: mockWebSession,
            urlSession: mockURLSession,
            cache: cache
        )

        // Configure mock to return 404
        MockURLProtocol.responseHandler = { request in
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
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockURLSession = URLSession(configuration: config)

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockWebSession = MetadataMockWebSession()

        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: MockTokenProvider(tokenValue: "test-token"),
            session: mockWebSession,
            urlSession: mockURLSession,
            cache: cache
        )

        // Configure mock to return 200 with valid metadata
        MockURLProtocol.responseHandler = { request in
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

    @Test("Includes Authorization header when token provider is present")
    func includesAuthorizationHeader() async throws {
        // Given
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockURLSession = URLSession(configuration: config)

        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockWebSession = MetadataMockWebSession()

        let service = PlaycutMetadataService(
            baseURL: URL(string: "https://api.wxyc.org")!,
            tokenProvider: MockTokenProvider(tokenValue: "my-secret-token"),
            session: mockWebSession,
            urlSession: mockURLSession,
            cache: cache
        )

        var capturedRequest: URLRequest?
        MockURLProtocol.responseHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
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
            """.data(using: .utf8)!
            return (body, response)
        }

        let playcut = Playcut.stub(
            songTitle: "Back, Baby",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again"
        )

        // When
        _ = await service.fetchMetadata(for: playcut)

        // Then
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer my-secret-token")
    }
}
