//
//  CacheCoordinatorDurabilityTests.swift
//  Caching
//
//  Tests for CacheCoordinator durability behavior: distinguishing intact-but-unreadable
//  entries from true absence, and the init purge re-checking metadata before removal so
//  a fresh write under a recycled key cannot be deleted from a stale snapshot.
//
//  Created by Jake Bromberg on 07/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Caching

@Suite("CacheCoordinator Durability Tests")
struct CacheCoordinatorDurabilityTests {

    // MARK: - Read failure vs. absence

    @Test("value(for:) throws readFailed for an intact but unreadable entry")
    func valueThrowsReadFailedWhenEntryIntactButUnreadable() async throws {
        let cache = UnreadableDataCache()
        let coordinator = CacheCoordinator(cache: cache)
        await coordinator.waitForPurge()

        await #expect(throws: CacheCoordinator.Error.readFailed) {
            let _: String = try await coordinator.value(for: UnreadableDataCache.intactKey)
        }

        // A transient read failure must not evict the intact entry.
        #expect(!cache.removedKeys.contains(UnreadableDataCache.intactKey))
    }

    @Test("data(for:) throws readFailed for an intact but unreadable entry")
    func dataThrowsReadFailedWhenEntryIntactButUnreadable() async throws {
        let cache = UnreadableDataCache()
        let coordinator = CacheCoordinator(cache: cache)
        await coordinator.waitForPurge()

        await #expect(throws: CacheCoordinator.Error.readFailed) {
            _ = try await coordinator.data(for: UnreadableDataCache.intactKey)
        }

        #expect(!cache.removedKeys.contains(UnreadableDataCache.intactKey))
    }

    @Test("A truly absent key still throws noCachedResult")
    func absentKeyStillThrowsNoCachedResult() async throws {
        let coordinator = CacheCoordinator(cache: InMemoryCache())
        await coordinator.waitForPurge()

        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            let _: String = try await coordinator.value(for: "never-written")
        }
    }

    @Test("value(for:) throws readFailed when metadata is unreadable")
    func valueThrowsReadFailedWhenMetadataUnreadable() async throws {
        let coordinator = CacheCoordinator(cache: UnreadableMetadataCache())
        await coordinator.waitForPurge()

        await #expect(throws: CacheCoordinator.Error.readFailed) {
            let _: String = try await coordinator.value(for: "intact")
        }
    }

    // MARK: - MigratingDiskCache unreadable-primary policy

    @Test("A readable-metadata primary with a failed data read does not migrate legacy")
    func unreadablePrimaryDataDoesNotMigrateLegacy() async throws {
        // Primary owns the entry (metadata present) but its data read fails
        // transiently. Falling through to legacy would resurrect a stale copy,
        // overwrite the intact newer primary, and delete the legacy original.
        let primary = ScriptedCache(metadataResult: .present(CacheMetadata(lifespan: 3600)), data: nil)
        let legacy = InMemoryCache()
        let staleLegacy = try JSONEncoder().encode("stale legacy value")
        legacy.set(staleLegacy, metadata: CacheMetadata(lifespan: 3600), for: "entry")
        let migrating = MigratingDiskCache(primary: primary, legacy: legacy)

        #expect(migrating.data(for: "entry") == nil)
        #expect(primary.setKeys.isEmpty, "the intact primary must not be overwritten by a legacy copy")
        #expect(legacy.data(for: "entry") != nil, "the legacy copy must not be destructively migrated")

        // The coordinator surfaces the condition as a read failure, not absence.
        let coordinator = CacheCoordinator(cache: migrating)
        await coordinator.waitForPurge()
        await #expect(throws: CacheCoordinator.Error.readFailed) {
            let _: String = try await coordinator.value(for: "entry")
        }
    }

    @Test("Init purge spares both stores when the primary is transiently unreadable")
    func purgeSparesUnreadablePrimaryWithExpiredLegacy() async throws {
        // The purge snapshot sees an expired lingering legacy copy; the primary is
        // transiently unreadable. Removing on that evidence would delete BOTH
        // stores — destroying the intact primary.
        let primary = ScriptedCache(metadataResult: .unreadable, data: nil)
        let legacy = InMemoryCache()
        let expired = CacheMetadata(
            timestamp: Date.timeIntervalSinceReferenceDate - 7200,
            lifespan: 3600
        )
        legacy.set(try JSONEncoder().encode("expired legacy"), metadata: expired, for: "entry")
        let migrating = MigratingDiskCache(primary: primary, legacy: legacy)

        let coordinator = CacheCoordinator(cache: migrating)
        await coordinator.waitForPurge()

        #expect(primary.removedKeys.isEmpty, "the unreadable primary must be spared")
        #expect(legacy.metadata(for: "entry") != nil, "the legacy copy must be spared too")

        await #expect(throws: CacheCoordinator.Error.readFailed) {
            let _: String = try await coordinator.value(for: "entry")
        }
    }

    // MARK: - Init purge ordering

    @Test("Writes wait for the init purge, so a concurrent write cannot be swept")
    func writesAreOrderedAfterInitPurge() async throws {
        // The purge holds a stale metadata snapshot while it runs; a write issued
        // during that window must not be observable until the purge completes.
        let cache = OrderRecordingCache(purgeDelay: 0.1)
        let coordinator = CacheCoordinator(cache: cache)

        await coordinator.set(value: "fresh value", for: "recycled", lifespan: 3600)
        await coordinator.waitForPurge()

        let events = cache.events
        let purgeEnd = try #require(events.firstIndex(of: "allMetadata:end"),
                                    "purge should have enumerated the cache")
        let firstWrite = try #require(events.firstIndex(of: "set:recycled"),
                                      "the write should have reached the cache")
        #expect(firstWrite > purgeEnd, "writes must strictly follow the init purge")

        let value: String = try await coordinator.value(for: "recycled")
        #expect(value == "fresh value")
    }

    // MARK: - Init purge re-check

    @Test("Init purge re-checks metadata before removing, sparing a recycled key")
    func initPurgeSparesFreshWriteUnderRecycledKey() async throws {
        // The snapshot claims the key is expired, but the live entry is fresh —
        // simulating a write that recycled the key between snapshot and removal.
        let inner = InMemoryCache()
        let encoded = try JSONEncoder().encode("fresh value")
        inner.set(encoded, metadata: CacheMetadata(lifespan: 3600), for: "recycled")
        let cache = StaleSnapshotCache(wrapping: inner, staleKeys: ["recycled"])

        let coordinator = CacheCoordinator(cache: cache)
        await coordinator.waitForPurge()

        let value: String = try await coordinator.value(for: "recycled")
        #expect(value == "fresh value")
    }

    @Test("Init purge still removes entries that are expired on re-check")
    func initPurgeRemovesEntriesExpiredOnRecheck() async throws {
        let inner = InMemoryCache()
        let encoded = try JSONEncoder().encode("stale value")
        let expired = CacheMetadata(
            timestamp: Date.timeIntervalSinceReferenceDate - 7200,
            lifespan: 3600
        )
        inner.set(encoded, metadata: expired, for: "expired-key")

        let coordinator = CacheCoordinator(cache: inner)
        await coordinator.waitForPurge()

        #expect(inner.metadata(for: "expired-key") == nil)
    }
}

// MARK: - Test Doubles

/// A cache holding one entry whose metadata is present but whose data cannot be read —
/// the shape DiskCache produces when `Data(contentsOf:)` fails on an intact file.
private final class UnreadableDataCache: Cache, @unchecked Sendable {
    static let intactKey = "intact"

    private let lock = NSLock()
    private var _removedKeys: Set<String> = []

    var removedKeys: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return _removedKeys
    }

    func metadata(for key: String) -> CacheMetadata? {
        key == Self.intactKey ? CacheMetadata(lifespan: 3600) : nil
    }

    func data(for key: String) -> Data? {
        nil
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {}

    func remove(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        _removedKeys.insert(key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        []
    }

    func clearAll() {}

    func totalSize() -> Int64 { 0 }
}

/// A cache with one scripted entry whose metadata result and data payload are fixed,
/// recording every write and removal — used to stand in for a DiskCache in a
/// transient failure state behind MigratingDiskCache.
private final class ScriptedCache: Cache, @unchecked Sendable {
    private let scriptedMetadataResult: MetadataReadResult
    private let scriptedData: Data?
    private let lock = NSLock()
    private var _setKeys: [String] = []
    private var _removedKeys: [String] = []

    init(metadataResult: MetadataReadResult, data: Data?) {
        self.scriptedMetadataResult = metadataResult
        self.scriptedData = data
    }

    var setKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _setKeys
    }

    var removedKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _removedKeys
    }

    func metadata(for key: String) -> CacheMetadata? {
        guard case .present(let metadata) = scriptedMetadataResult else { return nil }
        return metadata
    }

    func metadataResult(for key: String) -> MetadataReadResult {
        scriptedMetadataResult
    }

    func data(for key: String) -> Data? {
        scriptedData
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        _setKeys.append(key)
    }

    func remove(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        _removedKeys.append(key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        []
    }

    func clearAll() {}

    func totalSize() -> Int64 { 0 }
}

/// A cache whose metadata is present but unreadable — the shape DiskCache reports
/// when `getxattr` fails with an I/O or permission error on an intact file.
private final class UnreadableMetadataCache: Cache, @unchecked Sendable {
    func metadata(for key: String) -> CacheMetadata? {
        nil
    }

    func metadataResult(for key: String) -> MetadataReadResult {
        .unreadable
    }

    func data(for key: String) -> Data? {
        Data("payload".utf8)
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {}

    func remove(for key: String) {}

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        []
    }

    func clearAll() {}

    func totalSize() -> Int64 { 0 }
}

/// Wraps `InMemoryCache` and records the order of operations, stalling `allMetadata()`
/// so the init-purge window is wide enough for a concurrent write to land inside it.
private final class OrderRecordingCache: Cache, @unchecked Sendable {
    private let inner = InMemoryCache()
    private let lock = NSLock()
    private var _events: [String] = []
    private let purgeDelay: TimeInterval

    init(purgeDelay: TimeInterval) {
        self.purgeDelay = purgeDelay
    }

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    private func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(event)
    }

    func metadata(for key: String) -> CacheMetadata? {
        inner.metadata(for: key)
    }

    func data(for key: String) -> Data? {
        inner.data(for: key)
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        record("set:\(key)")
        inner.set(data, metadata: metadata, for: key)
    }

    func remove(for key: String) {
        record("remove:\(key)")
        inner.remove(for: key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        record("allMetadata:begin")
        Thread.sleep(forTimeInterval: purgeDelay)
        defer { record("allMetadata:end") }
        return inner.allMetadata()
    }

    func clearAll() {
        inner.clearAll()
    }

    func totalSize() -> Int64 {
        inner.totalSize()
    }
}

/// Wraps another cache but reports a stale, already-expired snapshot from `allMetadata()`
/// for the given keys, regardless of the live entries' actual metadata.
private final class StaleSnapshotCache: Cache, @unchecked Sendable {
    private let inner: InMemoryCache
    private let staleKeys: Set<String>

    init(wrapping inner: InMemoryCache, staleKeys: Set<String>) {
        self.inner = inner
        self.staleKeys = staleKeys
    }

    func metadata(for key: String) -> CacheMetadata? {
        inner.metadata(for: key)
    }

    func data(for key: String) -> Data? {
        inner.data(for: key)
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        inner.set(data, metadata: metadata, for: key)
    }

    func remove(for key: String) {
        inner.remove(for: key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        inner.allMetadata().map { entry in
            guard staleKeys.contains(entry.key) else { return entry }
            let stale = CacheMetadata(
                timestamp: Date.timeIntervalSinceReferenceDate - 7200,
                lifespan: 3600
            )
            return (entry.key, stale)
        }
    }

    func clearAll() {
        inner.clearAll()
    }

    func totalSize() -> Int64 {
        inner.totalSize()
    }
}
