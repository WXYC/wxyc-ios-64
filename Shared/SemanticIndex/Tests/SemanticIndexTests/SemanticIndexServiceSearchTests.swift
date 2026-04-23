//
//  SemanticIndexServiceSearchTests.swift
//  SemanticIndex
//
//  Tests for SemanticIndexService artist search functionality.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Core
@testable import Caching
@testable import SemanticIndex

@Suite("SemanticIndexService Search")
struct SemanticIndexServiceSearchTests {

    @Test("Constructs correct search URL with query and limit")
    func constructsCorrectSearchURL() async throws {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/search"] = """
        [{"id": 1, "canonical_name": "Stereolab", "genre": "Rock", "total_plays": 500}]
        """.data(using: .utf8)!

        _ = await service.searchArtist(name: "Stereolab")

        #expect(mockSession.requestCount == 1)
        let url = try #require(mockSession.requestedURLs.first)
        #expect(url.path().contains("graph/artists/search"))
        #expect(url.absoluteString.contains("q=Stereolab"))
        #expect(url.absoluteString.contains("limit=1"))
    }

    @Test("Decodes artist from search response")
    func decodesArtist() async throws {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/search"] = """
        [{"id": 42, "canonical_name": "Broadcast", "genre": "Electronic", "total_plays": 300}]
        """.data(using: .utf8)!

        let artist = await service.searchArtist(name: "Broadcast")

        let result = try #require(artist)
        #expect(result.id == 42)
        #expect(result.canonicalName == "Broadcast")
        #expect(result.genre == "Electronic")
        #expect(result.totalPlays == 300)
    }

    @Test("Returns nil when search returns empty array")
    func returnsNilForEmptyResults() async {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/search"] = "[]".data(using: .utf8)!

        let artist = await service.searchArtist(name: "Nonexistent Artist")
        #expect(artist == nil)
    }

    @Test("Returns nil when API errors")
    func returnsNilOnError() async {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        // No response configured — will throw

        let artist = await service.searchArtist(name: "Stereolab")
        #expect(artist == nil)
    }
}
