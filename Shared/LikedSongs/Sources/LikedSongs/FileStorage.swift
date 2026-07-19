//
//  FileStorage.swift
//  LikedSongs
//
//  Minimal durable-file seam for the likes store: load-once, atomic
//  write-through, never evicts. Deliberately NOT the Caching package —
//  CacheCoordinator purges infinite-lifespan entries at init and TTL-expires
//  finite ones, which is correct for re-derivable caches and data loss for
//  user-curated likes. See docs/plans/492-liked-songs.md decision #6.
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Synchronous durable storage for one file's worth of data. Payloads are KBs
/// (lean snapshots), so synchronous read-at-init and write-through keep heart
/// state correct at first paint with no load/toggle race.
public protocol FileStorage: Sendable {
    /// Returns the stored bytes, or nil when nothing has been saved yet.
    func load() throws -> Data?
    /// Persists the bytes atomically, replacing any prior contents.
    func save(_ data: Data) throws
}

/// `FileStorage` backed by a file in the app's Application Support directory.
public struct AppSupportFileStorage: FileStorage {
    private let fileURL: URL

    public init(filename: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent(filename)
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
