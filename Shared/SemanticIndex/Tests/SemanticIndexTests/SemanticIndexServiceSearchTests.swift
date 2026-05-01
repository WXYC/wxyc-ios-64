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
        {"results": [{"id": 1, "canonical_name": "Stereolab", "genre": "Rock", "total_plays": 500}]}
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
        {"results": [{"id": 42, "canonical_name": "Broadcast", "genre": "Electronic", "total_plays": 300}]}
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

        mockSession.responses["graph/artists/search"] = #"{"results": []}"#.data(using: .utf8)!

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

    @Test("Regression: decodes the production response shape (2026-04-30 incident)")
    func decodesProductionResponseShape() async throws {
        // 2026-04-30 incident: iOS metadata fetch failed for "The Paradise
        // Bangkok Molam International Band" with typeMismatch(Array<Any>,
        // "Expected to decode Array<Any> but found a dictionary instead").
        // The semantic-index API has always returned a wrapped
        // {"results": [...]} object — iOS was decoding a bare array. The mocks
        // used bare arrays too, so the test suite never caught the drift.
        // This test pins the iOS decoder to the real server contract.
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        // Verbatim production response body captured 2026-04-30 from
        // https://explore.wxyc.org/graph/artists/search?q=The+Paradise+Bangkok+Molam+International+Band&limit=1
        mockSession.responses["graph/artists/search"] = #"""
        {"results":[{"id":97426,"canonical_name":"the paradise bangkok molam international band","genre":null,"total_plays":58,"community_id":null,"pagerank":null}]}
        """#.data(using: .utf8)!

        let artist = await service.searchArtist(name: "The Paradise Bangkok Molam International Band")

        let result = try #require(artist)
        #expect(result.id == 97426)
        #expect(result.canonicalName == "the paradise bangkok molam international band")
        #expect(result.totalPlays == 58)
    }
}
