//
//  SemanticIndexServiceCachingTests.swift
//  SemanticIndex
//
//  Tests verifying that SemanticIndexService caches API responses and
//  avoids redundant network calls on subsequent fetches.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Core
@testable import Caching
@testable import SemanticIndex

@Suite("SemanticIndexService Caching")
struct SemanticIndexServiceCachingTests {

    @Test("Second search returns cached result without API call")
    func searchCachesResult() async throws {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/search"] = """
        [{"id": 42, "canonical_name": "Stereolab", "genre": "Rock", "total_plays": 500}]
        """.data(using: .utf8)!

        let first = await service.searchArtist(name: "Stereolab")
        let firstRequestCount = mockSession.requestCount

        let second = await service.searchArtist(name: "Stereolab")

        #expect(first?.id == 42)
        #expect(second?.id == 42)
        #expect(mockSession.requestCount == firstRequestCount, "Second search should use cache")
    }

    @Test("Second neighbors call returns cached result without API call")
    func neighborsCachesResult() async {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/42/neighbors"] = """
        [{"artist": {"id": 10, "canonical_name": "Tortoise", "genre": "Rock", "total_plays": 200}, "weight": 0.85}]
        """.data(using: .utf8)!

        let first = await service.neighbors(for: 42)
        let firstRequestCount = mockSession.requestCount

        let second = await service.neighbors(for: 42)

        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(mockSession.requestCount == firstRequestCount, "Second neighbors call should use cache")
    }

    @Test("Second artist detail call returns cached result without API call")
    func artistDetailCachesResult() async throws {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/42"] = """
        {"id": 42, "canonical_name": "Broadcast", "genre": "Electronic", "total_plays": 300}
        """.data(using: .utf8)!

        let first = await service.artistDetail(id: 42)
        let firstRequestCount = mockSession.requestCount

        let second = await service.artistDetail(id: 42)

        #expect(first?.canonicalName == "Broadcast")
        #expect(second?.canonicalName == "Broadcast")
        #expect(mockSession.requestCount == firstRequestCount, "Second detail call should use cache")
    }

    @Test("Different heat values use separate cache entries")
    func differentHeatValuesNotShared() async {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/42/neighbors"] = """
        [{"artist": {"id": 10, "canonical_name": "Tortoise", "genre": "Rock", "total_plays": 200}, "weight": 0.85}]
        """.data(using: .utf8)!

        _ = await service.neighbors(for: 42, heat: 0.0)
        let afterCool = mockSession.requestCount

        _ = await service.neighbors(for: 42, heat: 0.5)

        #expect(mockSession.requestCount == afterCool + 1, "Different heat should bypass cache")
    }
}
