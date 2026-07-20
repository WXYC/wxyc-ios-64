//
//  FileStorage.swift
//  Concerts
//
//  Minimal durable-file seam for the On Tour user-state stores: load-once,
//  atomic write-through, never evicts. Deliberately NOT the Caching package —
//  CacheCoordinator purges infinite-lifespan entries and TTL-expires the rest,
//  which is correct for re-derivable caches but data loss for user-curated state
//  like dismissed shows (the same rationale as the likes store's seam).
//
//  A deliberate mirror of `LikedSongs/FileStorage.swift`. Both are generic byte
//  seams; a future cleanup could hoist this pair into `Core` (which both packages
//  already depend on) to remove the duplication. Kept local for now so `Concerts`
//  gains no cross-feature dependency.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Synchronous durable storage for one file's worth of data. Payloads are tiny
/// (a set of dismissed concert ids), so synchronous read-at-init and write-through
/// keep the shelf correct at first paint with no load/dismiss race.
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
