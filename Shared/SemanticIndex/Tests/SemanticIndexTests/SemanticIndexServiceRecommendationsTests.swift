//
//  SemanticIndexServiceRecommendationsTests.swift
//  SemanticIndex
//
//  Tests for the convenience recommendations method that chains search + neighbors.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Core
@testable import Caching
@testable import SemanticIndex

@Suite("SemanticIndexService Recommendations")
struct SemanticIndexServiceRecommendationsTests {

    @Test("Chains search and neighbors for a known artist")
    func chainsSearchAndNeighbors() async throws {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/search"] = """
        {"results": [{"id": 42, "canonical_name": "Stereolab", "genre": "Rock", "total_plays": 500}]}
        """.data(using: .utf8)!

        mockSession.responses["graph/artists/42/neighbors"] = """
        {
            "artist": {"id": 42, "canonical_name": "Stereolab", "genre": "Rock", "total_plays": 500},
            "edge_type": "djTransition",
            "neighbors": [
                {
                    "artist": {"id": 10, "canonical_name": "Tortoise", "genre": "Rock", "total_plays": 200},
                    "weight": 0.85,
                    "detail": {"raw_count": 15, "pmi": 2.3}
                }
            ]
        }
        """.data(using: .utf8)!

        let recommendations = await service.recommendations(forArtistNamed: "Stereolab")

        #expect(recommendations.count == 1)
        #expect(recommendations[0].artist.canonicalName == "Tortoise")
        #expect(mockSession.requestCount == 2)
    }

    @Test("Returns empty when artist not found in graph")
    func returnsEmptyWhenArtistNotFound() async {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/search"] = #"{"results": []}"#.data(using: .utf8)!

        let recommendations = await service.recommendations(forArtistNamed: "Unknown")

        #expect(recommendations.isEmpty)
        // Should only make one call (search) — not proceed to neighbors
        #expect(mockSession.requestCount == 1)
    }

    @Test("Returns empty when search fails")
    func returnsEmptyWhenSearchFails() async {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        // No responses configured — search will fail

        let recommendations = await service.recommendations(forArtistNamed: "Stereolab")
        #expect(recommendations.isEmpty)
    }

    @Test("Returns empty when search succeeds but neighbors fails")
    func returnsEmptyWhenNeighborsFails() async {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/search"] = """
        {"results": [{"id": 42, "canonical_name": "Stereolab", "genre": "Rock", "total_plays": 500}]}
        """.data(using: .utf8)!

        // No neighbors response — will fail

        let recommendations = await service.recommendations(forArtistNamed: "Stereolab")
        #expect(recommendations.isEmpty)
    }
}
