//
//  InMemoryFileStorage.swift
//  Concerts
//
//  Test double for `FileStorage`: bytes held in memory behind a lock, so store
//  tests exercise the real load/decode/encode/save paths with no disk. Seed
//  `initial` to simulate an existing (or corrupt) store file.
//
//  Mirrors `LikedSongsTesting/InMemoryFileStorage.swift`.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Concerts

public final class InMemoryFileStorage: FileStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    private var _saveCount = 0

    public init(initial: Data? = nil) {
        stored = initial
    }

    public func load() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        stored = data
        _saveCount += 1
    }

    /// Number of `save(_:)` calls — lets tests assert write-through happens.
    public var saveCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _saveCount
    }

    /// The raw stored bytes, for round-trip assertions.
    public var contents: Data? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}
