//
//  InMemoryTokenStorage.swift
//  MusicShareKit
//
//  Thread-safe in-memory token storage for testing.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Thread-safe in-memory token storage for testing.
///
/// Use in tests for parallel execution without Keychain dependencies.
/// Each test can create its own instance, avoiding interference between parallel tests.
public final class InMemoryTokenStorage: TokenStorage, @unchecked Sendable {

    private var session: AuthSession?
    private let lock = NSLock()

    public init() {}

    public func load() throws -> AuthSession? {
        lock.withLock { session }
    }

    public func save(_ session: AuthSession) throws {
        lock.withLock { self.session = session }
    }

    public func delete() throws {
        lock.withLock { session = nil }
    }

    // MARK: - Test Helpers

    /// Resets the storage to empty state.
    public func reset() {
        lock.withLock { session = nil }
    }
}
