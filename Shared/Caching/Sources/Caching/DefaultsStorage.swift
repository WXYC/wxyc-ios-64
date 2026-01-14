//
//  DefaultsStorage.swift
//  Caching
//
//  Protocol abstracting UserDefaults for testability.
//  Enables parallel test execution via InMemoryDefaults.
//
//  Created by Jake Bromberg on 01/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Protocol abstracting UserDefaults for testability.
/// Enables parallel test execution via InMemoryDefaults.
public protocol DefaultsStorage: Sendable {

    // MARK: - Reading

    func object(forKey defaultName: String) -> Any?
    func bool(forKey defaultName: String) -> Bool
    func integer(forKey defaultName: String) -> Int
    func float(forKey defaultName: String) -> Float
    func double(forKey defaultName: String) -> Double
    func string(forKey defaultName: String) -> String?
    func data(forKey defaultName: String) -> Data?

    // MARK: - Writing

    func set(_ value: Any?, forKey defaultName: String)
    func set(_ value: Bool, forKey defaultName: String)
    func set(_ value: Int, forKey defaultName: String)
    func set(_ value: Float, forKey defaultName: String)
    func set(_ value: Double, forKey defaultName: String)

    // MARK: - Deletion

    func removeObject(forKey defaultName: String)

    // MARK: - Inspection

    /// Returns a dictionary containing all keys and values.
    /// Used by AdaptiveProfileStore for migration detection.
    func dictionaryRepresentation() -> [String: Any]
}

extension UserDefaults: DefaultsStorage {}
