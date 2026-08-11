//
//  DiscogsAPIEntityResolverCachingTests.swift
//  Metadata
//
//  Tests for DiscogsAPIEntityResolver caching functionality.
//  The resolver now calls the backend proxy at /proxy/entity/resolve.
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//
//  #761: `DiscogsAPIEntityResolver` dropped its dual `WebSession`/`URLSession`
//  fields in favor of a single `Core.WXYCProxyClient`, so its test-only
//  `session: WebSession` seam (`EntityResolverMockWebSession`) is gone too.
//  Cache-hit tests (which must never reach the network) now inject a
//  stateless `CoreTesting.FailFastURLProtocol`-backed session instead — no
//  mock object needed, since the assertion is just "no request was
//  attempted." Tests that DO need to observe a real request are declared as
//  extensions of `PlaycutMetadataServiceHTTPTests` and use
//  `CoreTesting.QueuedStubURLProtocol`, matching the convention already
//  established below for the 401 reauthenticate-and-retry test: that type's
//  state is static/global, so at most one adopting `@Suite` per test bundle
//  may touch it, and further adopters join as extensions of the existing one
//  rather than a parallel `@Suite`.
//
//  #786: `FailFastURLProtocol` used to be declared privately in this file —
//  it's now `CoreTesting.FailFastURLProtocol`, promoted so other packages
//  asserting "this must never touch the network" don't reinvent it. It stays
//  a genuinely distinct type from `QueuedStubURLProtocol` rather than folding
//  into it: it carries no lock/state at all, so — unlike everything above
//  that touches `QueuedStubURLProtocol` — the three tests below don't need
//  `.serialized` and don't contend for that type's one-adopter-per-bundle
//  slot.
//
//  On `FailFastURLProtocol` alone NOT being load-bearing for the three
//  cache-hit tests below: `cachedFetch` (Caching) returns straight from a
//  cache hit without ever calling `fetch`, so `urlSession` is never touched
//  in a passing run — mutating `FailFastURLProtocol` to succeed instead of
//  fail changes nothing observable. Each test now also asserts
//  `mockCache.setCallCount == 0`, since `cachedFetch` only calls `cache.set`
//  on its fetch-and-recache path, never on a hit — that is what actually
//  proves the fetch closure never ran, independent of what the injected
//  session would have done had it been reached.
//

import Testing
import Foundation
import Core
import CoreTesting
@testable import Caching
import CachingTesting
@testable import Metadata

// MARK: - DiscogsAPIEntityResolver Caching Tests

@Suite("DiscogsAPIEntityResolver Caching Tests")
struct DiscogsAPIEntityResolverCachingTests {

    @Test("resolveArtist returns cached name without API call")
    func resolveArtistReturnsCached() async throws {
        // Given
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let resolver = DiscogsAPIEntityResolver(urlSession: FailFastURLProtocol.makeSession(), cache: cache)

        // Pre-populate cache with artist name
        await cache.set(value: "Cached Artist Name", for: "discogs-artist-12345", lifespan: 3600)
        mockCache.reset()

        // When
        let result = try await resolver.resolveArtist(id: 12345)

        // Then — FailFastURLProtocol backs `urlSession` so a network attempt
        // would throw, but that alone isn't load-bearing here: a cache hit
        // never reaches `urlSession` at all, so this assertion would pass
        // identically whether the injected session failed or silently
        // succeeded. `setCallCount` is what actually proves no fetch-and-
        // recache happened — `cachedFetch` only calls `cache.set` on its
        // fetch path, never on a hit.
        #expect(result == "Cached Artist Name")
        #expect(mockCache.setCallCount == 0, "A cache hit must not fetch and recache")
    }

    @Test("resolveRelease returns cached title without API call")
    func resolveReleaseReturnsCached() async throws {
        // Given
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let resolver = DiscogsAPIEntityResolver(urlSession: FailFastURLProtocol.makeSession(), cache: cache)

        // Pre-populate cache
        await cache.set(value: "Cached Album Title", for: "discogs-release-54321", lifespan: 3600)
        mockCache.reset()

        // When
        let result = try await resolver.resolveRelease(id: 54321)

        // Then — see resolveArtistReturnsCached for why setCallCount, not
        // FailFastURLProtocol, is what actually proves no fetch happened.
        #expect(result == "Cached Album Title")
        #expect(mockCache.setCallCount == 0, "A cache hit must not fetch and recache")
    }

    @Test("resolveMaster returns cached title without API call")
    func resolveMasterReturnsCached() async throws {
        // Given
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let resolver = DiscogsAPIEntityResolver(urlSession: FailFastURLProtocol.makeSession(), cache: cache)

        // Pre-populate cache
        await cache.set(value: "Cached Master Title", for: "discogs-master-11111", lifespan: 3600)
        mockCache.reset()

        // When
        let result = try await resolver.resolveMaster(id: 11111)

        // Then — see resolveArtistReturnsCached for why setCallCount, not
        // FailFastURLProtocol, is what actually proves no fetch happened.
        #expect(result == "Cached Master Title")
        #expect(mockCache.setCallCount == 0, "A cache hit must not fetch and recache")
    }
}

// MARK: - Authenticated Init Regression Tests

/// Guards the public `init(tokenProvider:)` convenience initializer -- the one
/// `ArtistBioSection` constructs for every bio it renders. It must delegate to the
/// designated initializer; if it delegates to itself (an exact-arity match Swift's
/// overload resolution prefers over the designated init) it recurses until the stack
/// overflows. Merely constructing an instance without crashing is the assertion.
@Suite("DiscogsAPIEntityResolver Authenticated Init")
struct DiscogsAPIEntityResolverAuthInitTests {

    @Test("Authenticated convenience init delegates instead of recursing")
    func authenticatedInitDoesNotRecurse() {
        let resolver: DiscogsEntityResolver = DiscogsAPIEntityResolver(
            tokenProvider: RecordingTokenProvider(initialToken: "test-token")
        )
        #expect(resolver is DiscogsAPIEntityResolver)
    }

    @Test("Convenience init with a nil provider delegates instead of recursing")
    func nilProviderInitDoesNotRecurse() {
        let resolver: DiscogsEntityResolver = DiscogsAPIEntityResolver(tokenProvider: nil)
        #expect(resolver is DiscogsAPIEntityResolver)
    }
}

// MARK: - Network-backed tests (QueuedStubURLProtocol)
//
// Declared as an extension of `PlaycutMetadataServiceHTTPTests`
// (`PlaycutMetadataServiceHTTPTests.swift`) rather than their own `@Suite`:
// `QueuedStubURLProtocol`'s handler is shared global mutable state, and that
// suite's `.serialized` trait is what keeps concurrent tests from racing on
// it. A separate suite would run in parallel with it despite its own
// `.serialized` trait — traits only serialize *within* a suite, not across
// suites touching the same shared resource.
extension PlaycutMetadataServiceHTTPTests {

    @Test("resolveArtist fetches from backend proxy and caches on miss")
    func discogsResolveArtistFetchesAndCaches() async throws {
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let resolver = DiscogsAPIEntityResolver(urlSession: QueuedStubURLProtocol.makeSession(), cache: cache)

        QueuedStubURLProtocol.setBody(Data("""
        {
            "name": "New Artist From API",
            "type": "artist",
            "id": 99999
        }
        """.utf8))

        let result = try await resolver.resolveArtist(id: 99999)

        #expect(result == "New Artist From API")
        #expect(QueuedStubURLProtocol.capturedRequests().count == 1, "Should make exactly one API call")
        #expect(mockCache.setKeys.contains("discogs-artist-99999"), "Should cache the result")
    }

    @Test("resolveRelease fetches from backend proxy and caches on miss")
    func discogsResolveReleaseFetchesAndCaches() async throws {
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let resolver = DiscogsAPIEntityResolver(urlSession: QueuedStubURLProtocol.makeSession(), cache: cache)

        QueuedStubURLProtocol.setBody(Data("""
        {
            "name": "New Album From API",
            "type": "release",
            "id": 88888
        }
        """.utf8))

        let result = try await resolver.resolveRelease(id: 88888)

        #expect(result == "New Album From API")
        #expect(QueuedStubURLProtocol.capturedRequests().count == 1)
        #expect(mockCache.setKeys.contains("discogs-release-88888"))
    }

    @Test("resolveMaster fetches from backend proxy and caches on miss")
    func discogsResolveMasterFetchesAndCaches() async throws {
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let resolver = DiscogsAPIEntityResolver(urlSession: QueuedStubURLProtocol.makeSession(), cache: cache)

        QueuedStubURLProtocol.setBody(Data("""
        {
            "name": "New Master From API",
            "type": "master",
            "id": 77777
        }
        """.utf8))

        let result = try await resolver.resolveMaster(id: 77777)

        #expect(result == "New Master From API")
        #expect(QueuedStubURLProtocol.capturedRequests().count == 1)
        #expect(mockCache.setKeys.contains("discogs-master-77777"))
    }

    @Test("Second call returns cached result without additional API call")
    func discogsSecondCallReturnsCached() async throws {
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let resolver = DiscogsAPIEntityResolver(urlSession: QueuedStubURLProtocol.makeSession(), cache: cache)

        QueuedStubURLProtocol.setBody(Data("""
        {
            "name": "Test Artist",
            "type": "artist",
            "id": 33333
        }
        """.utf8))

        // When - first call
        let result1 = try await resolver.resolveArtist(id: 33333)
        let firstCallCount = QueuedStubURLProtocol.capturedRequests().count

        // When - second call
        let result2 = try await resolver.resolveArtist(id: 33333)
        let secondCallCount = QueuedStubURLProtocol.capturedRequests().count

        // Then
        #expect(result1 == "Test Artist")
        #expect(result2 == "Test Artist")
        #expect(firstCallCount == 1)
        #expect(secondCallCount == 1, "Second call should use cache, not make another API call")
    }

    @Test("Uses correct cache key format for each entity type")
    func discogsUsesCorrectCacheKeyFormat() async throws {
        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let resolver = DiscogsAPIEntityResolver(urlSession: QueuedStubURLProtocol.makeSession(), cache: cache)

        // Routes each request to the body matching its `type`/`id` query,
        // mirroring the retired `EntityResolverMockWebSession`'s
        // dictionary-based routing.
        let responses: [String: Data] = [
            "type=artist&id=1": #"{"name": "A", "type": "artist", "id": 1}"#.data(using: .utf8)!,
            "type=release&id=2": #"{"name": "R", "type": "release", "id": 2}"#.data(using: .utf8)!,
            "type=master&id=3": #"{"name": "M", "type": "master", "id": 3}"#.data(using: .utf8)!,
        ]
        QueuedStubURLProtocol.setHandler { request in
            let urlString = request.url?.absoluteString ?? ""
            guard let match = responses.first(where: { urlString.contains($0.key) }) else {
                throw URLError(.resourceUnavailable)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (match.value, response)
        }

        // When
        _ = try await resolver.resolveArtist(id: 1)
        _ = try await resolver.resolveRelease(id: 2)
        _ = try await resolver.resolveMaster(id: 3)

        // Then
        #expect(mockCache.setKeys.contains(MetadataCacheKey.discogsEntity(type: "artist", id: 1)))
        #expect(mockCache.setKeys.contains(MetadataCacheKey.discogsEntity(type: "release", id: 2)))
        #expect(mockCache.setKeys.contains(MetadataCacheKey.discogsEntity(type: "master", id: 3)))
    }

    // MARK: - 401 Reauthenticate-and-Retry Test (#414/#415)

    /// Exercises the authenticated `proxy/entity/resolve` request path against a
    /// stub `URLProtocol` on the injectable `urlSession`, so a rejected/stale
    /// cached token's 401 can be observed reauthenticating and retrying exactly
    /// once — the same seam `ConcertsFetcher` and `PlaycutMetadataService` use.
    @Test("Reauthenticates once and retries when DiscogsAPIEntityResolver's proxy/entity/resolve returns 401")
    func discogsEntityResolverRetriesOnceOn401ThenSucceeds() async throws {
        let mockURLSession = QueuedStubURLProtocol.makeSession()

        let mockCache = CountingCache()
        let cache = CacheCoordinator(cache: mockCache)
        let resolver = DiscogsAPIEntityResolver(
            tokenProvider: RecordingTokenProvider(initialToken: "stale-token", refreshedToken: "fresh-token"),
            urlSession: mockURLSession,
            cache: cache
        )

        QueuedStubURLProtocol.setResponses([
            (401, Data(#"{"error": "Unauthorized"}"#.utf8)),
            (200, Data(#"{"name": "Reauthenticated Artist", "type": "artist", "id": 4242}"#.utf8)),
        ])

        let result = try await resolver.resolveArtist(id: 4242)

        #expect(result == "Reauthenticated Artist")
        let capturedAuthorizationHeaders = QueuedStubURLProtocol.capturedRequests()
            .map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(capturedAuthorizationHeaders.count == 2)
        #expect(capturedAuthorizationHeaders[0] == "Bearer stale-token")
        #expect(capturedAuthorizationHeaders[1] == "Bearer fresh-token")
    }
}
