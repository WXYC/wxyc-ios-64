//
//  SemanticIndexServiceNeighborsTests.swift
//  SemanticIndex
//
//  Tests for SemanticIndexService neighbor/transition lookup functionality.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Core
@testable import Caching
@testable import SemanticIndex

@Suite("SemanticIndexService Neighbors")
struct SemanticIndexServiceNeighborsTests {

    @Test("Constructs correct neighbors URL with heat parameter")
    func constructsCorrectNeighborsURL() async throws {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/42/neighbors"] = #"{"artist": {"id": 42, "canonical_name": "Stereolab"}, "edge_type": "djTransition", "neighbors": []}"#.data(using: .utf8)!

        _ = await service.neighbors(for: 42, heat: 0.0, limit: 3)

        #expect(mockSession.requestCount == 1)
        let url = try #require(mockSession.requestedURLs.first)
        #expect(url.path().contains("graph/artists/42/neighbors"))
        #expect(url.absoluteString.contains("type=djTransition"))
        #expect(url.absoluteString.contains("heat=0.0"))
        #expect(url.absoluteString.contains("limit=3"))
    }

    @Test("Decodes neighbors with transition detail")
    func decodesNeighbors() async throws {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/42/neighbors"] = """
        {
            "artist": {"id": 42, "canonical_name": "Stereolab", "genre": "Rock", "total_plays": 500},
            "edge_type": "djTransition",
            "neighbors": [
                {
                    "artist": {"id": 10, "canonical_name": "Tortoise", "genre": "Rock", "total_plays": 200},
                    "weight": 0.85,
                    "detail": {"raw_count": 15, "pmi": 2.3}
                },
                {
                    "artist": {"id": 20, "canonical_name": "Laetitia Sadier", "genre": "Rock", "total_plays": 150},
                    "weight": 0.72,
                    "detail": {"raw_count": 10, "pmi": 1.8}
                }
            ]
        }
        """.data(using: .utf8)!

        let neighbors = await service.neighbors(for: 42)

        #expect(neighbors.count == 2)
        #expect(neighbors[0].artist.canonicalName == "Tortoise")
        #expect(neighbors[0].weight == 0.85)
        let detail = try #require(neighbors[0].detail)
        #expect(detail.rawCount == 15)
        #expect(detail.pmi == 2.3)
        #expect(neighbors[1].artist.canonicalName == "Laetitia Sadier")
    }

    @Test("Returns empty array on API error")
    func returnsEmptyOnError() async {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        let neighbors = await service.neighbors(for: 42)
        #expect(neighbors.isEmpty)
    }

    @Test("Regression: decodes the production neighbors response shape (2026-04-30 incident)")
    func decodesProductionResponseShape() async throws {
        // Same root cause as the search regression: the server has always
        // returned a wrapped object ({"artist", "edge_type", "neighbors"});
        // iOS was decoding a bare array of neighbors. This test pins iOS to
        // the real server contract using a verbatim production response.
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        // Verbatim production response body captured 2026-04-30 from
        // https://explore.wxyc.org/graph/artists/97426/neighbors?type=djTransition&heat=0.0&limit=3
        mockSession.responses["graph/artists/97426/neighbors"] = #"""
        {"artist":{"id":97426,"canonical_name":"the paradise bangkok molam international band","genre":null,"total_plays":58,"community_id":null,"pagerank":null},"edge_type":"djTransition","neighbors":[]}
        """#.data(using: .utf8)!

        let neighbors = await service.neighbors(for: 97426, heat: 0.0, limit: 3)
        #expect(neighbors.isEmpty)
    }
}
