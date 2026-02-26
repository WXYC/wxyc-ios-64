//
//  CacheAnalyticsTests.swift
//  Caching
//
//  Tests verifying error events are captured through injected analytics
//  on cache decode and encode failures.
//
//  Created by Jake Bromberg on 02/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Caching
import AnalyticsTesting

@Suite("CacheCoordinator Analytics")
struct CacheAnalyticsTests {

    @Test("Decode failure captures error event")
    func decodeFailureCapturesError() async throws {
        let mockCache = MockCache()
        let mockAnalytics = MockStructuredAnalytics()
        let coordinator = CacheCoordinator(cache: mockCache, clock: MockClock())
        await coordinator.setAnalytics(mockAnalytics)
        await coordinator.waitForPurge()

        // Store invalid JSON data
        let invalidData = Data("not json".utf8)
        let metadata = CacheMetadata(timestamp: 1_000_000, lifespan: 3600)
        mockCache.set(invalidData, metadata: metadata, for: "test-key")

        // Attempt to decode as a Codable type
        do {
            let _: TestCodable = try await coordinator.value(for: "test-key")
            Issue.record("Expected decoding to throw")
        } catch {
            // Expected
        }

        #expect(mockAnalytics.errorEvents.count == 1)
        #expect(mockAnalytics.errorEvents.first?.context == "CacheCoordinator decode value")
    }

    @Test("Encode failure captures error event")
    func encodeFailureCapturesError() async {
        let mockCache = MockCache()
        let mockAnalytics = MockStructuredAnalytics()
        let coordinator = CacheCoordinator(cache: mockCache, clock: MockClock())
        await coordinator.setAnalytics(mockAnalytics)
        await coordinator.waitForPurge()

        // Store a value that will fail to encode
        await coordinator.set(value: FailingCodable(), for: "test-key", lifespan: 3600)

        #expect(mockAnalytics.errorEvents.count == 1)
        #expect(mockAnalytics.errorEvents.first?.context == "CacheCoordinator encode value")
    }
}

// MARK: - Test Helpers

private struct TestCodable: Codable {
    let value: String
}

private struct FailingCodable: Codable {
    func encode(to encoder: Encoder) throws {
        throw EncodingError.invalidValue(
            self,
            EncodingError.Context(
                codingPath: [],
                debugDescription: "Intentional test failure"
            )
        )
    }
}
