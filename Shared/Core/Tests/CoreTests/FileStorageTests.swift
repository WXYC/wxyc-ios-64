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

    /// The one test that goes through the production `init(filename:)`.
    ///
    /// Every other `AppSupportFileStorage` test below uses the
    /// `init(directory:filename:)` sandbox seam, so without this the base
    /// directory would be pinned by nothing: swapping
    /// `.applicationSupportDirectory` for `.documentDirectory` would leave the
    /// whole suite green while relocating the user's liked songs and dismissed
    /// concerts. `Singletonia` builds both of its stores through this init and
    /// no other.
    ///
    /// Pure path arithmetic -- no `save`, so this doesn't reintroduce the
    /// container writes the sandbox seam exists to avoid.
    @Test("init(filename:) resolves against Application Support")
    func publicInitResolvesUnderApplicationSupport() throws {
        let base = try #require(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )

        let storage = AppSupportFileStorage(filename: "liked-songs.json")

        #expect(storage.fileURL == base.appendingPathComponent("liked-songs.json"))
    }

    @Test("A fresh AppSupportFileStorage with no file yet returns nil")
    func loadWithNoFileReturnsNil() throws {
        let (storage, sandbox) = makeAppSupportFileStorage()
        defer { removeSandbox(sandbox) }

        #expect(try storage.load() == nil)
    }

    @Test("save then load round-trips the exact bytes")
    func saveThenLoadRoundTrips() throws {
        let (storage, sandbox) = makeAppSupportFileStorage()
        defer { removeSandbox(sandbox) }

        let payload = Data("liked-songs-fixture".utf8)
        try storage.save(payload)
        #expect(try storage.load() == payload)
    }

    @Test("A second save atomically replaces the first")
    func secondSaveReplacesFirst() throws {
        let (storage, sandbox) = makeAppSupportFileStorage()
        defer { removeSandbox(sandbox) }

        try storage.save(Data("first".utf8))
        try storage.save(Data("second".utf8))
        #expect(try storage.load() == Data("second".utf8))
    }

    @Test("save creates any missing intermediate directories")
    func saveCreatesIntermediateDirectories() throws {
        let sandbox = makeSandbox()
        let storage = AppSupportFileStorage(directory: sandbox, filename: "nested/store.json")
        defer { removeSandbox(sandbox) }

        try storage.save(Data("nested".utf8))
        #expect(try storage.load() == Data("nested".utf8))
    }

    @Test("fileURL exposes the resolved path so callers can pin which file a store targets")
    func fileURLReflectsTheFilename() {
        let sandbox = makeSandbox()
        let storage = AppSupportFileStorage(directory: sandbox, filename: "store.json")
        defer { removeSandbox(sandbox) }

        #expect(storage.fileURL.lastPathComponent == "store.json")
    }

    @Test("A flat filename directly under the storage root round-trips")
    func flatFilenameRoundTrips() throws {
        // Production callers (Singletonia) pass a flat name like
        // "liked-songs.json" with no subdirectory, so
        // `deletingLastPathComponent()` in `save(_:)` resolves to the storage
        // root itself. The other tests above only ever exercise the nested
        // "<subdirectory>/store.json" shape.
        //
        // Against Application Support this case used to be weaker than it
        // looked: that directory always already exists, so `save(_:)`'s
        // `createDirectory` call was a no-op here and went unverified. The
        // sandbox root does not exist until `save(_:)` creates it, so the flat
        // case now exercises the same directory creation the nested ones do.
        let sandbox = makeSandbox()
        let filename = "liked-songs.json"
        let storage = AppSupportFileStorage(directory: sandbox, filename: filename)
        defer { removeSandbox(sandbox) }

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

    /// A unique temporary directory standing in for Application Support.
    ///
    /// These tests exercise the real `AppSupportFileStorage` -- its atomic
    /// write, its intermediate-directory creation, its `fileURL` resolution --
    /// so they need a real directory, but not *that* directory. Under
    /// `WXYC.xctestplan` the Application Support root is the WXYC app's own
    /// container, holding the user's real `liked-songs.json` and
    /// `dismissed-concerts.json`; a run killed mid-test used to leave fixture
    /// files sitting beside them, because cleanup is a best-effort `defer`.
    /// Leaking into `NSTemporaryDirectory()` costs nothing.
    private func makeSandbox() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "filestorage-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeAppSupportFileStorage() -> (AppSupportFileStorage, sandbox: URL) {
        let sandbox = makeSandbox()
        return (AppSupportFileStorage(directory: sandbox, filename: "store.json"), sandbox)
    }

    private func removeSandbox(_ sandbox: URL) {
        try? FileManager.default.removeItem(at: sandbox)
    }
}
