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

        let cachingErrors = capture.messages(level: .error, category: .caching)
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

        let cachingErrors = capture.messages(level: .error, category: .caching)
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

    @Test("purgeFiles removes regular files but preserves subdirectories")
    func purgeFilesPreservesSubdirectories() throws {
        // Given: a temp directory containing one file and one subdirectory.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("purge-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("loose-file")
        try Data("X".utf8).write(to: file)

        let subdir = root.appendingPathComponent("artwork-errors", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let nested = subdir.appendingPathComponent("inner-entry")
        try Data("Y".utf8).write(to: nested)

        // When
        CacheMigrationManager.purgeFiles(in: root)

        // Then: the loose file is gone, the subdirectory and its contents survive.
        #expect(!FileManager.default.fileExists(atPath: file.path),
                "Loose file should be deleted")
        #expect(FileManager.default.fileExists(atPath: subdir.path),
                "Subdirectory should be preserved so DiskCache(subdirectory:) keeps working")
        #expect(FileManager.default.fileExists(atPath: nested.path),
                "Files inside a subdirectory should be preserved too")
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
