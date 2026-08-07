//
//  FileStorage.swift
//  Core
//
//  Minimal durable-file seam: load-once, atomic write-through, never evicts.
//  Deliberately NOT the Caching package — CacheCoordinator purges
//  infinite-lifespan entries at init and TTL-expires finite ones, which is
//  correct for re-derivable caches and data loss for user-curated state.
//  See docs/plans/492-liked-songs.md decision #6.
//
//  Hoisted here from `LikedSongs` and `Concerts`, which each carried a
//  byte-for-byte-identical copy (the second, in `Concerts`, was a deliberate
//  mirror added in #555 to avoid a cross-feature dependency, with the
//  Core-hoist explicitly deferred). Both packages, plus the app target's
//  `-marketing` recording harness, now consume this one definition
//  (WXYC/wxyc-ios-64#557).
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Synchronous durable storage for one file's worth of data. Payloads are
/// small (lean snapshots or id sets), so synchronous read-at-init and
/// write-through keep state correct at first paint with no load/mutate race.
public protocol FileStorage: Sendable {
    /// Returns the stored bytes, or nil when nothing has been saved yet.
    func load() throws -> Data?
    /// Persists the bytes atomically, replacing any prior contents.
    func save(_ data: Data) throws
}

/// `FileStorage` backed by a file in the app's Application Support directory.
public struct AppSupportFileStorage: FileStorage {
    /// The resolved on-disk location. Public so callers with several
    /// `AppSupportFileStorage` instances in play (Singletonia routes both the
    /// likes and dismissed-concerts stores through this same type) can assert
    /// `fileURL.lastPathComponent` to confirm which file a given instance
    /// targets — the storage's `filename` init parameter has no other
    /// observable trace once constructed.
    public let fileURL: URL

    public init(filename: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(directory: base, filename: filename)
    }

    /// Resolves `filename` against `directory` rather than Application
    /// Support. `internal` because production always wants the real
    /// container; this exists so `FileStorageTests` can exercise the genuine
    /// `save`/`load`/`fileURL` behavior against a temporary directory. Under
    /// the simulator test plan the Application Support root is the WXYC app's
    /// own container -- the folder holding the user's real `liked-songs.json`
    /// and `dismissed-concerts.json` -- and a killed test run leaves its
    /// fixtures sitting next to them, since cleanup is a best-effort `defer`.
    init(directory: URL, filename: String) {
        self.fileURL = directory.appendingPathComponent(filename)
    }

    public func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    public func save(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
