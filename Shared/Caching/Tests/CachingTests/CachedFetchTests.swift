//
//  CachedFetchTests.swift
//  Caching
//
//  Tests for the CachedFetch utility that encapsulates the check-cache, fetch,
//  decode, store, and fallback workflow used across multiple services.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Caching

// MARK: - CachedFetch Tests

@Suite("CachedFetch Tests")
struct CachedFetchTests {

    // MARK: - Cache Hit

    @Test("Returns cached value without calling fetch closure")
    func returnsCachedValueWithoutFetch() async throws {
        // Given
        let cache = CacheCoordinator(cache: InMemoryCache())
        await cache.set(value: "cached result", for: "key", lifespan: 3600)
        var fetchCalled = false

        // When
        let result: String = try await cachedFetch(
            key: "key",
            cache: cache,
            lifespan: 3600,
            fetch: {
                fetchCalled = true
                return "fetched result"
            }
        )

        // Then
        #expect(result == "cached result")
        #expect(!fetchCalled)
    }

    // MARK: - Cache Miss

    @Test("Fetches and caches value on cache miss")
    func fetchesAndCachesOnMiss() async throws {
        // Given
        let cache = CacheCoordinator(cache: InMemoryCache())

        // When
        let result: String = try await cachedFetch(
            key: "key",
            cache: cache,
            lifespan: 3600,
            fetch: { "fetched result" }
        )

        // Then
        #expect(result == "fetched result")
        let cached: String = try await cache.value(for: "key")
        #expect(cached == "fetched result")
    }

    // MARK: - Fetch Error Propagation

    @Test("Propagates fetch errors when no fallback is provided")
    func propagatesFetchErrors() async throws {
        // Given
        let cache = CacheCoordinator(cache: InMemoryCache())

        // When/Then
        await #expect(throws: TestFetchError.networkFailure) {
            let _: String = try await cachedFetch(
                key: "key",
                cache: cache,
                lifespan: 3600,
                fetch: { throw TestFetchError.networkFailure }
            )
        }
    }

    // MARK: - Fallback on Error

    @Test("Returns fallback value when fetch fails")
    func returnsFallbackOnFetchError() async throws {
        // Given
        let cache = CacheCoordinator(cache: InMemoryCache())

        // When
        let result: String = try await cachedFetch(
            key: "key",
            cache: cache,
            lifespan: 3600,
            fetch: { throw TestFetchError.networkFailure },
            fallback: { "fallback value" }
        )

        // Then
        #expect(result == "fallback value")
    }

    @Test("Does not cache fallback values")
    func doesNotCacheFallbackValues() async throws {
        // Given
        let cache = CacheCoordinator(cache: InMemoryCache())

        // When
        let _: String = try await cachedFetch(
            key: "key",
            cache: cache,
            lifespan: 3600,
            fetch: { throw TestFetchError.networkFailure },
            fallback: { "fallback value" }
        )

        // Then
        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            let _: String = try await cache.value(for: "key")
        }
    }

    // MARK: - Transform

    @Test("Applies transform to fetched value before caching")
    func appliesTransformBeforeCaching() async throws {
        // Given
        let cache = CacheCoordinator(cache: InMemoryCache())

        // When
        let result: String = try await cachedFetch(
            key: "key",
            cache: cache,
            lifespan: 3600,
            fetch: { "  raw value  " },
            transform: { $0.trimmingCharacters(in: .whitespaces) }
        )

        // Then
        #expect(result == "raw value")
        let cached: String = try await cache.value(for: "key")
        #expect(cached == "raw value")
    }

    // MARK: - Expired Cache

    @Test("Fetches fresh value when cache entry has expired")
    func fetchesFreshValueOnExpiredCache() async throws {
        // Given
        let mockClock = MockClock()
        let cache = CacheCoordinator(cache: InMemoryCache(), clock: mockClock)
        await cache.set(value: "stale", for: "key", lifespan: 60)
        mockClock.advance(by: 61)

        // When
        let result: String = try await cachedFetch(
            key: "key",
            cache: cache,
            lifespan: 60,
            fetch: { "fresh" }
        )

        // Then
        #expect(result == "fresh")
    }

    // MARK: - Custom Codable Types

    @Test("Works with custom Codable structs")
    func worksWithCustomCodableStructs() async throws {
        // Given
        let cache = CacheCoordinator(cache: InMemoryCache())
        let expected = CachedPerson(name: "Juana Molina", age: 62)

        // When
        let result: CachedPerson = try await cachedFetch(
            key: "person",
            cache: cache,
            lifespan: 3600,
            fetch: { expected }
        )

        // Then
        #expect(result == expected)
    }

    // MARK: - Different Fetch and Cache Types

    @Test("Transforms fetched type to a different cached type")
    func transformsFetchedTypeToDifferentCachedType() async throws {
        // Given
        let cache = CacheCoordinator(cache: InMemoryCache())
        let rawResponse = RawAPIResponse(value: "42", label: "answer")

        // When
        let result: ParsedResult = try await cachedFetch(
            key: "parsed",
            cache: cache,
            lifespan: 3600,
            fetch: { rawResponse },
            transform: { ParsedResult(number: Int($0.value) ?? 0, label: $0.label) }
        )

        // Then
        #expect(result.number == 42)
        #expect(result.label == "answer")
    }

    // MARK: - Fallback with Transform and Error

    @Test("Returns fallback when transform throws")
    func returnsFallbackWhenTransformThrows() async throws {
        // Given
        let cache = CacheCoordinator(cache: InMemoryCache())

        // When
        let result: String = try await cachedFetch(
            key: "key",
            cache: cache,
            lifespan: 3600,
            fetch: { "raw" },
            transform: { (_: String) -> String in throw TestFetchError.transformFailure },
            fallback: { "fallback" }
        )

        // Then
        #expect(result == "fallback")
    }

    @Test("Propagates transform error when no fallback provided")
    func propagatesTransformErrorWhenNoFallback() async throws {
        // Given
        let cache = CacheCoordinator(cache: InMemoryCache())

        // When/Then
        await #expect(throws: TestFetchError.transformFailure) {
            let _: String = try await cachedFetch(
                key: "key",
                cache: cache,
                lifespan: 3600,
                fetch: { "raw" },
                transform: { (_: String) -> String in throw TestFetchError.transformFailure }
            )
        }
    }
}

// MARK: - Test Helpers

private enum TestFetchError: Error {
    case networkFailure
    case transformFailure
}

private struct CachedPerson: Codable, Equatable, Sendable {
    let name: String
    let age: Int
}

private struct RawAPIResponse: Codable, Sendable {
    let value: String
    let label: String
}

private struct ParsedResult: Codable, Equatable, Sendable {
    let number: Int
    let label: String
}
