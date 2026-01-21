//
//  TokenStorage.swift
//  MusicShareKit
//
//  Protocol abstracting token storage for testability.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Protocol for storing and retrieving authentication sessions.
///
/// Implementations should be thread-safe as the storage may be accessed
/// from multiple contexts concurrently.
public protocol TokenStorage: Sendable {

    /// Loads the stored authentication session.
    ///
    /// - Returns: The stored session, or `nil` if none exists.
    /// - Throws: `AuthenticationError.keychainError` if the read operation fails.
    func load() throws -> AuthSession?

    /// Saves an authentication session.
    ///
    /// - Parameter session: The session to save.
    /// - Throws: `AuthenticationError.keychainError` if the write operation fails.
    func save(_ session: AuthSession) throws

    /// Deletes the stored authentication session.
    ///
    /// - Throws: `AuthenticationError.keychainError` if the delete operation fails.
    func delete() throws
}
