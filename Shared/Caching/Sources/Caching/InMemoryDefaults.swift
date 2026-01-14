//
//  InMemoryDefaults.swift
//  Caching
//
//  Thread-safe in-memory storage conforming to DefaultsStorage.
//  Use in tests for parallel execution without disk I/O or cleanup.
//
//  Created by Jake Bromberg on 01/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Thread-safe in-memory storage conforming to DefaultsStorage.
///
/// Use in tests for parallel execution without disk I/O or cleanup.
/// Each test can create its own instance, avoiding interference between parallel tests.
///
/// - Note: Does not support KVO or automatic type coercion like `UserDefaults`.
///   For example, storing `Int(1)` and reading as `Bool` returns `false`, not `true`.
public final class InMemoryDefaults: DefaultsStorage, @unchecked Sendable {

    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    public init() {}

    // MARK: - Reading

    public func object(forKey defaultName: String) -> Any? {
        lock.withLock { storage[defaultName] }
    }

    public func bool(forKey defaultName: String) -> Bool {
        object(forKey: defaultName) as? Bool ?? false
    }

    public func integer(forKey defaultName: String) -> Int {
        object(forKey: defaultName) as? Int ?? 0
    }

    public func float(forKey defaultName: String) -> Float {
        object(forKey: defaultName) as? Float ?? 0
    }

    public func double(forKey defaultName: String) -> Double {
        object(forKey: defaultName) as? Double ?? 0
    }

    public func string(forKey defaultName: String) -> String? {
        object(forKey: defaultName) as? String
    }

    public func data(forKey defaultName: String) -> Data? {
        object(forKey: defaultName) as? Data
    }

    // MARK: - Writing

    public func set(_ value: Any?, forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
    }

    public func set(_ value: Bool, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    public func set(_ value: Int, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    public func set(_ value: Float, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    public func set(_ value: Double, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    // MARK: - Deletion

    public func removeObject(forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: defaultName)
    }

    // MARK: - Inspection

    public func dictionaryRepresentation() -> [String: Any] {
        lock.withLock { storage }
    }

    // MARK: - Test Helpers

    /// Clears all stored values. Useful for test setup/teardown.
    public func reset() {
        lock.withLock { storage.removeAll() }
    }
}
