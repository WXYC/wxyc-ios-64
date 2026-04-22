//
//  KeychainTokenStorage.swift
//  MusicShareKit
//
//  Keychain-backed token storage for anonymous authentication sessions.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Core
import Foundation
import Security

/// Keychain-backed token storage for anonymous authentication sessions.
///
/// Stores authentication sessions in the device Keychain. Anonymous session tokens
/// are device-specific and not synchronized via iCloud Keychain (see issue #210).
public final class KeychainTokenStorage: TokenStorage, @unchecked Sendable {

    /// The service name for Keychain items.
    private let service: String

    /// The account name for the anonymous session.
    private let account: String

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
    ///   - synchronizable: Whether to sync via iCloud Keychain. Defaults to `false`.
    ///                      Anonymous session tokens are device-specific and should not sync.
    ///   - analytics: Analytics service for tracking keychain errors.
    public init(accessGroup: String?, synchronizable: Bool = false, analytics: AnalyticsService) {
        self.service = "org.wxyc.app.auth"
        self.account = "anonymous-session"
        self.accessGroup = accessGroup
        self.synchronizable = synchronizable
        self.analytics = analytics
    }

    /// Creates a Keychain token storage with custom service and account names.
    /// Used for testing with isolated Keychain items.
    init(
        service: String,
        account: String,
        accessGroup: String?,
        synchronizable: Bool,
        analytics: AnalyticsService
    ) {
        self.service = service
        self.account = account
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
                let session = try JSONDecoder.shared.decode(AuthSession.self, from: data)
                return session
            } catch {
                trackKeychainError(operation: .read, status: errSecDecode)
                throw AuthenticationError.keychainError(status: errSecDecode)
            }

        case errSecItemNotFound:
            // One-time migration: check for items saved with the old synchronizable=true
            // setting (issue #210). If found, migrate to non-synchronizable storage.
            if !synchronizable {
                return migrateFromSynchronizable()
            }
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
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
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

    /// Attempts to find and migrate a session saved with `kSecAttrSynchronizable = true`.
    ///
    /// Prior to issue #210, anonymous session tokens were stored as synchronizable
    /// Keychain items (iCloud Keychain sync). This caused persistence failures when
    /// iCloud Keychain was unavailable, creating a new anonymous user on every launch.
    ///
    /// This method searches for any item matching the service/account regardless of
    /// sync status, and if found, re-saves it as a non-synchronizable item.
    ///
    /// - Returns: The migrated session, or `nil` if no synchronizable item was found
    ///   or migration failed.
    private func migrateFromSynchronizable() -> AuthSession? {
        // Build a standalone query (not baseQuery) that finds items regardless of sync status
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        // Decode the session
        let session: AuthSession
        do {
            session = try JSONDecoder.shared.decode(AuthSession.self, from: data)
        } catch {
            analytics.capture(RequestLineKeychainMigratedEvent(success: false))
            return nil
        }

        // Delete the old synchronizable item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Re-save as non-synchronizable (lock is already held by load())
        let newData: Data
        do {
            newData = try JSONEncoder().encode(session)
        } catch {
            analytics.capture(RequestLineKeychainMigratedEvent(success: false))
            return nil
        }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = newData
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus != errSecSuccess {
            analytics.capture(RequestLineKeychainMigratedEvent(success: false))
            // Still return the session — it's valid, just couldn't persist the migration
            return session
        }

        analytics.capture(RequestLineKeychainMigratedEvent(success: true))
        return session
    }

    private func trackKeychainError(operation: KeychainOperation, status: OSStatus) {
        analytics.capture(RequestLineKeychainErrorEvent(
            operation: operation,
            osStatus: status
        ))
    }
}
