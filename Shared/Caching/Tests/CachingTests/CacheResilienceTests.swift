//
//  CacheResilienceTests.swift
//  Caching
//
//  Tests that DiskCache and CacheMigrationManager recover gracefully when
//  the cache directory or files are removed out from under them (e.g. by
//  a version-bump purge wiping a DiskCache subdirectory).
//
//  Created by Jake Bromberg on 05/17/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Logger
@testable import Caching

// MARK: - DiskCache.remove

/// Serialized because Logger destinations are process-global.
@Suite("DiskCache.remove resilience", .serialized)
struct DiskCacheRemoveResilienceTests {

    @Test("remove(for:) does not log when the entry never existed")
    func removeAbsentKeyDoesNotLog() {
        let capture = LogCapture()
        Logger.addDestination(capture)
        defer { Logger.removeAllDestinations() }

        let cache = DiskCache()
        let key = "never-existed-\(UUID().uuidString)"

        cache.remove(for: key)

        // Filter to this test's key: the destination is process-global, so
        // parallel suites exercising failure paths may log unrelated errors.
        let cachingErrors = capture.messages(level: .error, category: .caching)
            .filter { $0.contains(key) }
        #expect(cachingErrors.isEmpty,
                "remove(for:) should be a silent no-op for missing entries; got: \(cachingErrors)")
    }

    @Test("remove(for:) does not log when the file was deleted externally")
    func removeFileDeletedExternallyDoesNotLog() throws {
        let cache = DiskCache()
        let key = "externally-deleted-\(UUID().uuidString)"
        cache.set(Data("X".utf8), metadata: CacheMetadata(lifespan: 3600), for: key)

        // Simulate purgeAllCaches wiping the file out from under us.
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = cachesDir.appendingPathComponent(key)
        try FileManager.default.removeItem(at: fileURL)

        let capture = LogCapture()
        Logger.addDestination(capture)
        defer { Logger.removeAllDestinations() }

        cache.remove(for: key)

        // Filter to this test's key: the destination is process-global, so
        // parallel suites exercising failure paths may log unrelated errors.
        let cachingErrors = capture.messages(level: .error, category: .caching)
            .filter { $0.contains(key) }
        #expect(cachingErrors.isEmpty,
                "remove(for:) should not log when the file was already gone; got: \(cachingErrors)")
    }
}

// MARK: - DiskCache.set self-healing

@Suite("DiskCache subdirectory self-healing")
struct DiskCacheSubdirectoryHealingTests {

    @Test("set(_:) recreates the subdirectory if it was removed externally")
    func setRecreatesMissingSubdirectory() throws {
        let subdir = "healing-test-\(UUID().uuidString)"
        let cache = DiskCache(subdirectory: subdir)

        // The init created the subdirectory. Simulate CacheMigrationManager
        // walking Library/Caches/ and removing entries (including subdirectories).
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let subdirURL = cachesDir.appendingPathComponent(subdir, isDirectory: true)
        try FileManager.default.removeItem(at: subdirURL)
        #expect(!FileManager.default.fileExists(atPath: subdirURL.path))

        // When: subsequent writes happen against a DiskCache whose backing dir is gone.
        let key = "post-purge-\(UUID().uuidString)"
        let payload = Data("self-heal".utf8)
        cache.set(payload, metadata: CacheMetadata(lifespan: 3600), for: key)

        // Then: the directory is recreated and the entry is readable.
        #expect(FileManager.default.fileExists(atPath: subdirURL.path),
                "set(_:) should recreate the missing subdirectory")
        #expect(cache.data(for: key) == payload,
                "Entry should be retrievable after self-healing")

        // Cleanup
        try? FileManager.default.removeItem(at: subdirURL)
    }
}

// MARK: - CacheMigrationManager subdirectory preservation

@Suite("CacheMigrationManager.purgeFiles")
struct CacheMigrationManagerPurgeTests {

    @Test("purgeFiles clears the root's top level, scopes recursion by xattr, and spares temps")
    func purgeFilesContract() throws {
        // Given: a purge root mixing DiskCache entries, pre-xattr-era legacy files,
        // an in-flight temp, and foreign subdirectories — the Library/Caches roots
        // are shared with Sentry's envelope queue and NSURLCache among others.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("purge-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let metadata = CacheMetadata(lifespan: 3600)

        let taggedFile = root.appendingPathComponent("tagged-entry")
        try Data("X".utf8).write(to: taggedFile)
        DiskCache.writeMetadataAttribute(metadata, to: taggedFile)

        // Pre-xattr-era WXYC cache file: no metadata attribute, but it's ours —
        // the top level of a purge root has been WXYC-owned for years.
        let legacyFile = root.appendingPathComponent("legacy-pre-xattr-entry")
        try Data("old format".utf8).write(to: legacyFile)

        // Another process's mid-write temp: tagged (the xattr lands before
        // rename), but deleting it would make that rename fail and lose the write.
        let inflightTemp = root.appendingPathComponent(".tmp-in-flight")
        try Data("in flight".utf8).write(to: inflightTemp)
        DiskCache.writeMetadataAttribute(metadata, to: inflightTemp)

        let cacheSubdir = root.appendingPathComponent("artwork-errors", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheSubdir, withIntermediateDirectories: true)
        let nestedTagged = cacheSubdir.appendingPathComponent("inner-entry")
        try Data("Y".utf8).write(to: nestedTagged)
        DiskCache.writeMetadataAttribute(metadata, to: nestedTagged)

        let foreignSubdir = root.appendingPathComponent("io.sentry", isDirectory: true)
        try FileManager.default.createDirectory(at: foreignSubdir, withIntermediateDirectories: true)
        let envelope = foreignSubdir.appendingPathComponent("envelope-1")
        try Data("crash report".utf8).write(to: envelope)

        // When
        CacheMigrationManager.purgeFiles(in: root)

        // Then: the root's top level is cleared regardless of tagging (foreign
        // subsystems park in subdirectories, and pre-xattr WXYC files must not
        // become permanent cruft), recursion into subdirectories deletes only
        // xattr-tagged files, temps are never touched, and directory nodes survive.
        #expect(!FileManager.default.fileExists(atPath: taggedFile.path),
                "Tagged top-level entry should be deleted")
        #expect(!FileManager.default.fileExists(atPath: legacyFile.path),
                "Pre-xattr-era top-level file should be deleted, not stranded forever")
        #expect(FileManager.default.fileExists(atPath: inflightTemp.path),
                "An in-flight temp must be spared — the init sweep owns stale-temp cleanup")
        #expect(!FileManager.default.fileExists(atPath: nestedTagged.path),
                "Tagged entry inside a cache subdirectory should be deleted")
        #expect(FileManager.default.fileExists(atPath: envelope.path),
                "Foreign subdirectory contents (e.g. Sentry envelopes) must survive")
        #expect(FileManager.default.fileExists(atPath: cacheSubdir.path),
                "Directory nodes should be preserved so DiskCache(subdirectory:) keeps working")
        #expect(FileManager.default.fileExists(atPath: foreignSubdir.path))
    }
}

// MARK: - Test Doubles

private final class LogCapture: LogDestination, @unchecked Sendable {
    struct Entry {
        let level: LogLevel
        let category: LogCategory
        let message: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func receive(level: LogLevel, category: LogCategory, message: String) {
        lock.withLock {
            entries.append(Entry(level: level, category: category, message: message))
        }
    }

    func messages(level: LogLevel, category: LogCategory) -> [String] {
        lock.withLock {
            entries
                .filter { $0.level == level && $0.category == category }
                .map(\.message)
        }
    }
}
