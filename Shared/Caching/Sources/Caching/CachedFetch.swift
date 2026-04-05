//
//  CachedFetch.swift
//  Caching
//
//  Generic fetch-and-cache utility that encapsulates the check-cache, fetch,
//  decode, store, and fallback workflow. Eliminates duplicated boilerplate
//  across services that follow this pattern.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Fetches a `Codable` value using a check-cache-then-fetch workflow.
///
/// This function encapsulates a pattern repeated across many services:
/// 1. Check the cache for an existing value
/// 2. On miss, call the `fetch` closure to obtain a raw value
/// 3. Transform the raw value into the cached type
/// 4. Store the result in the cache with the specified lifespan
/// 5. On error, return a fallback value
///
/// ## Usage
///
/// ```swift
/// let metadata: ArtistMetadata = try await cachedFetch(
///     key: "artist-123",
///     cache: cache,
///     lifespan: .thirtyDays,
///     fetch: { try await api.fetchArtist(id: 123) },
///     transform: { ArtistMetadata(bio: $0.bio, url: $0.url) },
///     fallback: { .empty }
/// )
/// ```
///
/// - Parameters:
///   - key: The cache key for storage and retrieval.
///   - cache: The ``CacheCoordinator`` to use for caching.
///   - lifespan: How long the cached entry should remain valid, in seconds.
///   - fetch: An async throwing closure that fetches the raw value from the network or other source.
///   - transform: A closure that transforms the fetched value into the cached type.
///   - fallback: A closure that provides a fallback value when both cache lookup and fetch fail.
/// - Returns: The cached, fetched, or fallback value.
public func cachedFetch<Fetched: Codable & Sendable, Cached: Codable & Sendable>(
    key: String,
    cache: CacheCoordinator,
    lifespan: TimeInterval,
    fetch: sending () async throws -> Fetched,
    transform: sending (Fetched) throws -> Cached,
    fallback: sending () -> Cached
) async throws -> Cached {
    if let cached: Cached = try? await cache.value(for: key) {
        return cached
    }

    do {
        let raw = try await fetch()
        let result = try transform(raw)
        await cache.set(value: result, for: key, lifespan: lifespan)
        return result
    } catch {
        return fallback()
    }
}

/// Fetches a `Codable` value using a check-cache-then-fetch workflow, propagating errors.
///
/// Same as the fallback variant, but errors from `fetch` or `transform` are propagated
/// to the caller instead of being caught.
///
/// ## Usage
///
/// ```swift
/// let name: String = try await cachedFetch(
///     key: "artist-123",
///     cache: cache,
///     lifespan: .thirtyDays,
///     fetch: { try await api.fetchArtistName(id: 123) },
///     transform: { $0.name }
/// )
/// ```
///
/// - Parameters:
///   - key: The cache key for storage and retrieval.
///   - cache: The ``CacheCoordinator`` to use for caching.
///   - lifespan: How long the cached entry should remain valid, in seconds.
///   - fetch: An async throwing closure that fetches the raw value from the network or other source.
///   - transform: A closure that transforms the fetched value into the cached type.
/// - Returns: The cached or fetched value.
/// - Throws: The error from `fetch` or `transform`.
public func cachedFetch<Fetched: Codable & Sendable, Cached: Codable & Sendable>(
    key: String,
    cache: CacheCoordinator,
    lifespan: TimeInterval,
    fetch: sending () async throws -> Fetched,
    transform: sending (Fetched) throws -> Cached
) async throws -> Cached {
    if let cached: Cached = try? await cache.value(for: key) {
        return cached
    }

    let raw = try await fetch()
    let result = try transform(raw)
    await cache.set(value: result, for: key, lifespan: lifespan)
    return result
}

/// Convenience overload when the fetched type is the same as the cached type (no transform needed).
///
/// - Parameters:
///   - key: The cache key for storage and retrieval.
///   - cache: The ``CacheCoordinator`` to use for caching.
///   - lifespan: How long the cached entry should remain valid, in seconds.
///   - fetch: An async throwing closure that fetches the value.
///   - fallback: A closure providing a fallback value on failure.
/// - Returns: The cached, fetched, or fallback value.
public func cachedFetch<Value: Codable & Sendable>(
    key: String,
    cache: CacheCoordinator,
    lifespan: TimeInterval,
    fetch: sending () async throws -> Value,
    fallback: sending () -> Value
) async throws -> Value {
    try await cachedFetch(
        key: key,
        cache: cache,
        lifespan: lifespan,
        fetch: fetch,
        transform: { $0 },
        fallback: fallback
    )
}

/// Convenience overload when the fetched type is the same as the cached type and errors should propagate.
///
/// - Parameters:
///   - key: The cache key for storage and retrieval.
///   - cache: The ``CacheCoordinator`` to use for caching.
///   - lifespan: How long the cached entry should remain valid, in seconds.
///   - fetch: An async throwing closure that fetches the value.
/// - Returns: The cached or fetched value.
/// - Throws: The error from `fetch`.
public func cachedFetch<Value: Codable & Sendable>(
    key: String,
    cache: CacheCoordinator,
    lifespan: TimeInterval,
    fetch: sending () async throws -> Value
) async throws -> Value {
    try await cachedFetch(
        key: key,
        cache: cache,
        lifespan: lifespan,
        fetch: fetch,
        transform: { $0 }
    )
}
