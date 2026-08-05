//
//  FileStorageTests.swift
//  Core
//
//  Tests for the `FileStorage` seam: the durable byte-file protocol,
//  `AppSupportFileStorage` (its Application Support-backed production
//  implementation), and `InMemoryFileStorage` (its `CoreTesting` double).
//  Hoisted from `LikedSongs`/`Concerts`, which each carried an identical copy
//  (WXYC/wxyc-ios-64#557) — this is the first direct coverage of the seam
//  itself; previously it was only exercised indirectly through
//  `LikedSongsStoreTests`/`DismissedConcertsStoreTests`.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import CoreTesting
@testable import Core

@Suite("FileStorage Tests")
struct FileStorageTests {

    // MARK: - AppSupportFileStorage

    @Test("A fresh AppSupportFileStorage with no file yet returns nil")
    func loadWithNoFileReturnsNil() throws {
        let (storage, subdirectory) = makeAppSupportFileStorage()
        defer { removeApplicationSupportSubdirectory(subdirectory) }

        #expect(try storage.load() == nil)
    }

    @Test("save then load round-trips the exact bytes")
    func saveThenLoadRoundTrips() throws {
        let (storage, subdirectory) = makeAppSupportFileStorage()
        defer { removeApplicationSupportSubdirectory(subdirectory) }

        let payload = Data("liked-songs-fixture".utf8)
        try storage.save(payload)
        #expect(try storage.load() == payload)
    }

    @Test("A second save atomically replaces the first")
    func secondSaveReplacesFirst() throws {
        let (storage, subdirectory) = makeAppSupportFileStorage()
        defer { removeApplicationSupportSubdirectory(subdirectory) }

        try storage.save(Data("first".utf8))
        try storage.save(Data("second".utf8))
        #expect(try storage.load() == Data("second".utf8))
    }

    @Test("save creates any missing intermediate directories")
    func saveCreatesIntermediateDirectories() throws {
        let subdirectory = "filestorage-test-\(UUID().uuidString)"
        let storage = AppSupportFileStorage(filename: "\(subdirectory)/nested/store.json")
        defer { removeApplicationSupportSubdirectory(subdirectory) }

        try storage.save(Data("nested".utf8))
        #expect(try storage.load() == Data("nested".utf8))
    }

    @Test("fileURL exposes the resolved path so callers can pin which file a store targets")
    func fileURLReflectsTheFilename() {
        let subdirectory = "filestorage-test-\(UUID().uuidString)"
        let storage = AppSupportFileStorage(filename: "\(subdirectory)/store.json")
        defer { removeApplicationSupportSubdirectory(subdirectory) }

        #expect(storage.fileURL.lastPathComponent == "store.json")
    }

    @Test("A flat filename directly under Application Support round-trips")
    func flatFilenameRoundTrips() throws {
        // Production callers (Singletonia) pass a flat name like "liked-songs.json"
        // with no subdirectory, so `deletingLastPathComponent()` in `save(_:)`
        // resolves to the Application Support root itself. The other tests above
        // only ever exercise the nested "<uuid>/store.json" shape.
        let filename = "filestorage-flat-test-\(UUID().uuidString).json"
        let storage = AppSupportFileStorage(filename: filename)
        defer { removeApplicationSupportFile(filename) }

        #expect(storage.fileURL.lastPathComponent == filename)
        try storage.save(Data("flat".utf8))
        #expect(try storage.load() == Data("flat".utf8))
    }

    // MARK: - InMemoryFileStorage (CoreTesting)

    @Test("A fresh InMemoryFileStorage with no seed returns nil")
    func inMemoryStartsEmpty() throws {
        let storage = InMemoryFileStorage()
        #expect(try storage.load() == nil)
        #expect(storage.saveCount == 0)
    }

    @Test("InMemoryFileStorage can be seeded with initial bytes")
    func inMemorySeedsInitialContents() throws {
        let seed = Data("seeded".utf8)
        let storage = InMemoryFileStorage(initial: seed)
        #expect(try storage.load() == seed)
    }

    @Test("save records the bytes and increments saveCount")
    func inMemorySaveRecordsBytesAndCount() throws {
        let storage = InMemoryFileStorage()
        try storage.save(Data("a".utf8))
        try storage.save(Data("b".utf8))
        #expect(storage.saveCount == 2)
        #expect(storage.contents == Data("b".utf8))
        #expect(try storage.load() == Data("b".utf8))
    }

    // MARK: - Helpers

    private func makeAppSupportFileStorage() -> (AppSupportFileStorage, subdirectory: String) {
        let subdirectory = "filestorage-test-\(UUID().uuidString)"
        return (AppSupportFileStorage(filename: "\(subdirectory)/store.json"), subdirectory)
    }

    private func removeApplicationSupportSubdirectory(_ subdirectory: String) {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        try? FileManager.default.removeItem(at: base.appending(path: subdirectory))
    }

    private func removeApplicationSupportFile(_ filename: String) {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        try? FileManager.default.removeItem(at: base.appending(path: filename))
    }
}
