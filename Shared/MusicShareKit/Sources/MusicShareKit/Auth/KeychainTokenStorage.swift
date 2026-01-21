//
//  KeychainTokenStorage.swift
//  MusicShareKit
//
//  Keychain-backed token storage with iCloud sync support.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Foundation
import Security

/// Keychain-backed token storage with iCloud sync support.
///
/// Stores authentication sessions in the Keychain with optional iCloud synchronization
/// for seamless device-to-device session sharing.
public final class KeychainTokenStorage: TokenStorage, @unchecked Sendable {

    /// The service name for Keychain items.
    private static let service = "org.wxyc.app.auth"

    /// The account name for the anonymous session.
    private static let account = "anonymous-session"

    /// The Keychain access group for sharing between app and extensions.
    private let accessGroup: String?

    /// Whether to sync the token via iCloud Keychain.
    private let synchronizable: Bool

    /// Analytics service for tracking keychain operations.
    private let analytics: AnalyticsService

    private let lock = NSLock()

    /// Creates a new Keychain token storage.
    ///
    /// - Parameters:
    ///   - accessGroup: The Keychain access group for sharing between targets.
    ///                  Pass `nil` for app-only storage. Format: `$(TeamID).group.name`
    ///   - synchronizable: Whether to sync via iCloud Keychain. Defaults to `true`.
    ///   - analytics: Analytics service for tracking keychain errors.
    public init(accessGroup: String?, synchronizable: Bool = true, analytics: AnalyticsService) {
        self.accessGroup = accessGroup
        self.synchronizable = synchronizable
        self.analytics = analytics
    }

    // MARK: - TokenStorage

    public func load() throws -> AuthSession? {
        lock.lock()
        defer { lock.unlock() }

        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                trackKeychainError(operation: .read, status: errSecParam)
                throw AuthenticationError.keychainError(status: errSecParam)
            }
            do {
                let session = try JSONDecoder().decode(AuthSession.self, from: data)
                return session
            } catch {
                trackKeychainError(operation: .read, status: errSecDecode)
                throw AuthenticationError.keychainError(status: errSecDecode)
            }

        case errSecItemNotFound:
            return nil

        default:
            trackKeychainError(operation: .read, status: status)
            throw AuthenticationError.keychainError(status: status)
        }
    }

    public func save(_ session: AuthSession) throws {
        lock.lock()
        defer { lock.unlock() }

        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            trackKeychainError(operation: .write, status: errSecParam)
            throw AuthenticationError.keychainError(status: errSecParam)
        }

        // Try to update existing item first
        var query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist, add it
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if synchronizable {
                query[kSecAttrSynchronizable as String] = true
            }
            status = SecItemAdd(query as CFDictionary, nil)
        }

        if status != errSecSuccess {
            trackKeychainError(operation: .write, status: status)
            throw AuthenticationError.keychainError(status: status)
        }
    }

    public func delete() throws {
        lock.lock()
        defer { lock.unlock() }

        let query = baseQuery()
        let status = SecItemDelete(query as CFDictionary)

        // Treat "not found" as success for delete operations
        if status != errSecSuccess && status != errSecItemNotFound {
            trackKeychainError(operation: .delete, status: status)
            throw AuthenticationError.keychainError(status: status)
        }
    }

    // MARK: - Private

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Include synchronizable in query to match items regardless of sync status
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }

        return query
    }

    private func trackKeychainError(operation: KeychainOperation, status: OSStatus) {
        analytics.capture(RequestLineKeychainErrorEvent(
            operation: operation,
            osStatus: status
        ))
    }
}
