//
//  DiskCacheDurabilityTests.swift
//  Caching
//
//  Tests for DiskCache durability: atomic overwrites (data + metadata xattr land
//  together, with no observable xattr-less window) and the Application Support
//  storage location for irreplaceable data.
//
//  Created by Jake Bromberg on 07/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Logger
import LoggerTesting
@testable import Caching

@Suite("DiskCache Durability Tests")
struct DiskCacheDurabilityTests {

    // MARK: - Atomic writes

    @Test("Concurrent reader never observes an entry without metadata during overwrites")
    func overwritesAreAtomicUnderConcurrentReads() async throws {
        let subdirectory = "atomic-test-\(UUID().uuidString)"
        let cache = DiskCache(subdirectory: subdirectory)
        defer { removeCachesSubdirectory(subdirectory) }

        let metadata = CacheMetadata(lifespan: 3600)
        cache.set(Data("initial".utf8), metadata: metadata, for: "entry")

        // Overwrite in a detached task while reading on this one. A non-atomic
        // write (data file replaced before its metadata xattr lands) is observable
        // as a nil metadata/data read — and worse, the metadata read purges the
        // "legacy" file, destroying the fresh write. The reader is gated on the
        // writer having started and stops when it finishes, so every read pass
        // genuinely overlaps writes — the test cannot pass vacuously.
        let progress = WriterProgress()
        let writer = Task.detached {
            for iteration in 0..<400 {
                cache.set(Data("value-\(iteration)".utf8), metadata: metadata, for: "entry")
                if iteration == 0 { progress.started = true }
            }
            progress.finished = true
        }

        while !progress.started {
            await Task.yield()
        }
        var missingObservations = 0
        var overlappedPasses = 0
        while !progress.finished {
            if cache.metadata(for: "entry") == nil || cache.data(for: "entry") == nil {
                missingObservations += 1
            }
            overlappedPasses += 1
        }
        await writer.value

        #expect(missingObservations == 0)
        #expect(overlappedPasses > 0, "the reader must have raced the writer for the test to prove anything")
        #expect(cache.data(for: "entry") != nil)
        #expect(cache.metadata(for: "entry") != nil)
    }

    @Test("Overwriting an entry replaces both data and metadata")
    func overwriteReplacesDataAndMetadata() throws {
        let subdirectory = "atomic-test-\(UUID().uuidString)"
        let cache = DiskCache(subdirectory: subdirectory)
        defer { removeCachesSubdirectory(subdirectory) }

        cache.set(Data("first".utf8), metadata: CacheMetadata(lifespan: 60), for: "entry")
        cache.set(Data("second".utf8), metadata: CacheMetadata(lifespan: 120), for: "entry")

        #expect(cache.data(for: "entry") == Data("second".utf8))
        #expect(cache.metadata(for: "entry")?.lifespan == 120)
        // No stray temp files should be visible as cache entries.
        #expect(cache.allMetadata().map(\.key) == ["entry"])
    }

    // MARK: - Filesystem-unsafe keys

    // Cache keys are opaque strings, but the artwork/palette keyers build them
    // from artist and release text — e.g. "AC/DC-Back in Black". A '/' in the key
    // is a path separator to `appendingPathComponent`, so the naive mapping points
    // the atomic temp write at an implied subdirectory that `set` never creates,
    // and the write fails with ENOENT ("temp file … doesn't exist"). The mapping
    // must fold such characters into a single safe path component.
    @Test("A key containing a path separator round-trips through disk storage",
          arguments: ["AC/DC-Back in Black", "him/her-split single", "a/b/c-nested"])
    func slashContainingKeyRoundTrips(key: String) throws {
        let subdirectory = "slash-test-\(UUID().uuidString)"
        let cache = DiskCache(subdirectory: subdirectory)
        defer { removeCachesSubdirectory(subdirectory) }

        cache.set(Data("artwork".utf8), metadata: CacheMetadata(lifespan: 3600), for: key)

        #expect(cache.data(for: key) == Data("artwork".utf8),
                "a slash-bearing key must persist to and read back from disk")
        #expect(cache.metadata(for: key)?.lifespan == 3600)
        #expect(cache.allMetadata().map(\.key) == [key],
                "the entry must enumerate under its original key, not a phantom subdirectory")
    }

    @Test("Distinct slash-bearing keys do not collide on disk")
    func slashContainingKeysDoNotCollide() throws {
        let subdirectory = "slash-collision-\(UUID().uuidString)"
        let cache = DiskCache(subdirectory: subdirectory)
        defer { removeCachesSubdirectory(subdirectory) }

        // "AC/DC" and "AC-DC" must not fold onto the same filename — a lossy
        // sanitizer (slash -> dash) would serve one artist's artwork for the other.
        cache.set(Data("slash".utf8), metadata: CacheMetadata(lifespan: 3600), for: "AC/DC")
        cache.set(Data("dash".utf8), metadata: CacheMetadata(lifespan: 3600), for: "AC-DC")

        #expect(cache.data(for: "AC/DC") == Data("slash".utf8))
        #expect(cache.data(for: "AC-DC") == Data("dash".utf8))
    }

    // A key with no reserved character must map to a byte-identical filename, or
    // the encoding silently invalidates every entry a prior build wrote under the
    // raw key. WXYC's freeform catalog is full of diacritics (Nilüfer Yanya,
    // Hermanos Gutiérrez), which a naive `addingPercentEncoding` escapes because it
    // always percent-escapes non-ASCII regardless of the allowed set — the mapping
    // must escape only the three reserved characters and leave Unicode untouched.
    @Test("A key without reserved characters keeps a byte-identical filename",
          arguments: ["Nilüfer Yanya-PAINLESS", "Hermanos Gutiérrez-El Bueno y el Malo",
                      "Sigur Rós-Ágætis byrjun", "Björk-Homogenic", "plain-ascii-key"])
    func nonReservedKeyMapsToIdenticalFilename(key: String) throws {
        #expect(DiskCache.encodedFilename(for: key) == key,
                "a key free of '/', '%', and NUL must not be percent-encoded, or existing on-disk entries stop resolving")
        #expect(DiskCache.decodedKey(fromFilename: DiskCache.encodedFilename(for: key)) == key)
    }

    // MARK: - Temp-file hygiene

    @Test("Coordinator init purge sweeps stale temps in a subdirectory-scoped cache")
    func coordinatorPurgeSweepsStaleTempFiles() async throws {
        let subdirectory = "sweep-test-\(UUID().uuidString)"
        defer { removeCachesSubdirectory(subdirectory) }

        // Seed the directory (and one real entry) BEFORE the coordinator exists —
        // the sweep must run from the coordinator's async purge task, not from
        // DiskCache.init, which can execute on the main actor at launch.
        let cache = DiskCache(subdirectory: subdirectory)
        cache.set(Data("keep".utf8), metadata: CacheMetadata(lifespan: 3600), for: "entry")

        let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let directory = caches.appending(path: subdirectory)

        // An old orphan (crash leftover) and a young temp (possibly another
        // process's in-flight write).
        let oldOrphan = directory.appending(path: ".tmp-old-orphan")
        try Data("orphan".utf8).write(to: oldOrphan)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-2 * 60 * 60)],
            ofItemAtPath: oldOrphan.path
        )
        let youngTemp = directory.appending(path: ".tmp-in-flight")
        try Data("in flight".utf8).write(to: youngTemp)

        let coordinator = CacheCoordinator(cache: cache)
        await coordinator.waitForPurge()

        #expect(!FileManager.default.fileExists(atPath: oldOrphan.path),
                "stale orphaned temp should be swept by the coordinator's purge task")
        #expect(FileManager.default.fileExists(atPath: youngTemp.path),
                "young temp may be another process's in-flight write and must be spared")
        #expect(cache.data(for: "entry") == Data("keep".utf8))
    }

    @Test("Root-scoped caches sweep only stale temps bearing our metadata xattr")
    func rootScopedSweepIsOwnershipScoped() async throws {
        // At a shared root (no subdirectory) a name-only '.tmp-' match could
        // delete foreign files; ownership must be proven by the xattr there.
        let cache = DiskCache()
        let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)

        let staleDate = Date.now.addingTimeInterval(-2 * 60 * 60)
        let ourTemp = caches.appending(path: ".tmp-ours-\(UUID().uuidString)")
        try Data("ours".utf8).write(to: ourTemp)
        DiskCache.writeMetadataAttribute(CacheMetadata(lifespan: 3600), to: ourTemp)
        try FileManager.default.setAttributes([.modificationDate: staleDate], ofItemAtPath: ourTemp.path)

        let foreignTemp = caches.appending(path: ".tmp-foreign-\(UUID().uuidString)")
        try Data("foreign".utf8).write(to: foreignTemp)
        try FileManager.default.setAttributes([.modificationDate: staleDate], ofItemAtPath: foreignTemp.path)
        defer {
            try? FileManager.default.removeItem(at: ourTemp)
            try? FileManager.default.removeItem(at: foreignTemp)
        }

        let coordinator = CacheCoordinator(cache: cache)
        await coordinator.waitForPurge()

        #expect(!FileManager.default.fileExists(atPath: ourTemp.path),
                "our stale orphan at the root should be swept")
        #expect(FileManager.default.fileExists(atPath: foreignTemp.path),
                "a foreign '.tmp-'-named file at the shared root must be spared")
    }

    @Test("writeMetadataAttribute reports failure for a missing file")
    func writeMetadataAttributeReportsFailure() throws {
        // The Bool result is what writeAtomically keys its abandon path on:
        // installing an xattr-less file would get it deleted by the legacy purge.
        // This exercises the reporting, not the abandon path itself — setxattr
        // failure on an existing temp isn't inducible on a healthy filesystem.
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString)")
        #expect(DiskCache.writeMetadataAttribute(CacheMetadata(lifespan: 60), to: missing) == false)
    }

    // MARK: - Unreadable metadata

    @Test("An unreadable metadata attribute does not destroy the entry")
    func unreadableMetadataDoesNotPurgeEntry() throws {
        try #require(geteuid() != 0, "EACCES cannot be induced as root")
        let subdirectory = "unreadable-test-\(UUID().uuidString)"
        let cache = DiskCache(subdirectory: subdirectory)
        defer { removeCachesSubdirectory(subdirectory) }

        cache.set(Data("history".utf8), metadata: CacheMetadata(lifespan: 3600), for: "entry")
        let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let fileURL = caches.appending(path: subdirectory).appending(path: "entry")

        // Revoke read permission: getxattr now fails with EACCES — a transient,
        // non-ENOATTR failure that must not be mistaken for a legacy xattr-less
        // file and purged.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path) }

        #expect(cache.metadata(for: "entry") == nil, "metadata is unavailable while unreadable")
        if case .absent = cache.metadataResult(for: "entry") {
            Issue.record("an unreadable attribute must not classify as absent")
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path),
                "the intact entry must not be deleted on a transient read failure")

        // Once readable again, the entry is fully recoverable.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        #expect(cache.metadata(for: "entry") != nil)
        #expect(cache.data(for: "entry") == Data("history".utf8))
    }

    @Test("A file without the metadata attribute is still purged as legacy")
    func missingAttributeStillPurgesLegacyFile() throws {
        let subdirectory = "legacy-test-\(UUID().uuidString)"
        let cache = DiskCache(subdirectory: subdirectory)
        defer { removeCachesSubdirectory(subdirectory) }

        let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let fileURL = caches.appending(path: subdirectory).appending(path: "legacy")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old-format".utf8).write(to: fileURL)

        #expect(cache.metadata(for: "legacy") == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path),
                "an xattr-less file is definitively legacy and should be purged")
    }

    // MARK: - Storage location

    @Test("applicationSupport location roots the cache under Application Support and stays backed up")
    func applicationSupportLocationRootsUnderApplicationSupport() throws {
        let subdirectory = "durability-test-\(UUID().uuidString)"
        let base = try #require(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        defer { try? FileManager.default.removeItem(at: base.appending(path: subdirectory)) }

        // Simulate a directory created by an intermediate build that marked it
        // excluded from backup: initialization must affirmatively clear the flag.
        var preExisting = base.appending(path: subdirectory)
        try FileManager.default.createDirectory(at: preExisting, withIntermediateDirectories: true)
        var markExcluded = URLResourceValues()
        markExcluded.isExcludedFromBackup = true
        try preExisting.setResourceValues(markExcluded)

        let cache = DiskCache(location: .applicationSupport(subdirectory: subdirectory))
        cache.set(Data("history".utf8), metadata: CacheMetadata(lifespan: 3600), for: "entry")

        let directory = base.appending(path: subdirectory)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "entry").path))
        #expect(cache.data(for: "entry") == Data("history".utf8))

        // Irreplaceable, locally-accreted data must be INCLUDED in backups —
        // it cannot be re-created after a device restore. The clear is
        // best-effort per init (and re-runs on every launch in production), so
        // under parallel-suite disk churn the flag is re-checked through fresh
        // initializations rather than on a single racy read.
        var isExcluded = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        for _ in 0..<5 where isExcluded != false {
            _ = DiskCache(location: .applicationSupport(subdirectory: subdirectory))
            let freshRead = URL(fileURLWithPath: directory.path, isDirectory: true)
            isExcluded = try freshRead.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        }
        #expect(isExcluded == false)
    }
}

// MARK: - Helpers

/// File-scoped so both suites in this file share one cleanup path.
private func removeCachesSubdirectory(_ subdirectory: String) {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        return
    }
    try? FileManager.default.removeItem(at: caches.appending(path: subdirectory))
}

// MARK: - Rename-failure reporting

/// Serialized because ``ErrorReporting/shared`` is a process-global.
@Suite("DiskCache writeAtomically rename-failure reporting", .serialized)
struct DiskCacheRenameFailureReportingTests {

    @Test("A failed rename during an atomic write is reported through ErrorReporting, not only os_log")
    func renameFailureIsReportedThroughErrorReporting() throws {
        let subdirectory = "rename-failure-\(UUID().uuidString)"
        let cache = DiskCache(subdirectory: subdirectory)
        defer { removeCachesSubdirectory(subdirectory) }

        let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let cacheDirectory = caches.appending(path: subdirectory)
        let destination = cacheDirectory.appending(path: "entry")

        // rename(2) fails with EISDIR when "to" already exists as a directory and
        // "from" is a regular file (the atomic write's temp file always is) — a
        // deterministic way to force the rename leg to fail that doesn't depend on
        // permission bits, which don't induce a failure when tests run as root.
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let mockReporter = MockErrorReporter()
        let previousReporter = ErrorReporting.shared
        ErrorReporting.shared = mockReporter
        defer { ErrorReporting.shared = previousReporter }

        cache.set(Data("payload".utf8), metadata: CacheMetadata(lifespan: 3600), for: "entry")

        let renameErrors = mockReporter.errors(in: "DiskCache writeAtomically: rename")
        #expect(!renameErrors.isEmpty,
                "a failed rename must be reported through ErrorReporting, not just os_log — a persistent rename outage is a silent total write outage")

        // Pins the errno capture, not just the report: the value has to be the
        // one rename(2) actually set. Reading the ambient errno later — as this
        // leg used to — can surface whatever an intervening libc call left behind.
        let report = try #require(renameErrors.first)
        #expect(report.category == .caching)
        #expect(report.additionalData["file"] == "entry")
        #expect(report.additionalData["errno"] == "\(EISDIR)",
                "the reported errno must be the one rename(2) set (EISDIR), captured inside the closure")

        #expect(FileManager.default.fileExists(atPath: destination.path),
                "the pre-existing directory (standing in for an intact prior entry) must survive an abandoned rename")

        // The abandoned write must not leak its temp file into the cache directory.
        let leftovers = try FileManager.default
            .contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            .filter(DiskCache.isTempFile)
        #expect(leftovers.isEmpty, "an abandoned rename must clean up its temp file")
    }
}

// MARK: - Test Doubles

/// Lock-guarded flags letting the stress test's reader confirm genuine overlap
/// with the writer instead of racing past it.
private final class WriterProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _started = false
    private var _finished = false

    var started: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _started
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _started = newValue
        }
    }

    var finished: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _finished
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _finished = newValue
        }
    }
}
