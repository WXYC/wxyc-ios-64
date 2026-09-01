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
/// Stores authentication sessions in the Keychain with optional iCloud synchronization
/// for cross-device session persistence. A save whose synchronizable add fails retries
/// without the flag, so sessions still persist across app launches (see issue #210).
/// That retry is not the path taken by a device with iCloud Keychain switched off. On
/// iOS it is a last resort on an already-failing add; on macOS it is load-bearing,
/// because the flag selects which Keychain the item goes to. See `save()`, iOS#1035
/// and iOS#1037.
public final class KeychainTokenStorage: TokenStorage, @unchecked Sendable {

    /// The service name for Keychain items.
    private let service: String

    /// The account name for the anonymous session.
    private let account: String

    /// The Keychain access group to scope items to, or `nil` for the process
    /// default. Per-target, not shared — see `MusicShareKitConfiguration`.
    private let accessGroup: String?

    /// Whether to sync the token via iCloud Keychain.
    private let synchronizable: Bool

    /// Analytics service for tracking keychain operations.
    private let analytics: AnalyticsService

    private let lock = NSLock()

    /// Creates a new Keychain token storage.
    ///
    /// - Parameters:
    ///   - accessGroup: The Keychain access group to scope items to. Pass
    ///                  `nil` to use the process default. Format is
    ///                  `<App ID prefix>.<group name>`; the prefix is not
    ///                  necessarily the Team ID (#996).
    ///   - synchronizable: Whether to sync via iCloud Keychain. Defaults to `true`.
    ///                      When `true`, a save whose synchronizable add fails
    ///                      retries without the flag. That retry is not what
    ///                      an iCloud-Keychain-off device takes, and what it
    ///                      is for differs by platform — see `save()`,
    ///                      iOS#1035 and iOS#1037.
    ///   - analytics: Analytics service for tracking keychain errors.
    public init(accessGroup: String?, synchronizable: Bool = true, analytics: AnalyticsService) {
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
            // Fallback: when synchronizable=true, baseQuery includes
            // kSecAttrSynchronizableAny which should match both sync and non-sync
            // items. But if the query still found nothing, check without the sync
            // flag in case of edge cases (issue #210).
            if synchronizable {
                return loadNonSynchronizable()
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

        // Try to update existing item first (matches both sync and non-sync items)
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

            // Retry without the sync flag when the synchronizable add fails.
            // Not, as this comment used to claim, because iCloud Keychain is
            // unavailable: a synchronizable add succeeds with iCloud Keychain
            // off and with no iCloud account, so no device arrives here for
            // that reason (iOS#1035).
            //
            // What the retry is actually for is platform-dependent, and
            // iOS#1035 stated only the iOS half.
            //
            // On iOS there is one Keychain, so kSecAttrSynchronizable is not
            // the attribute a missing entitlement / wrong access group /
            // not-yet-unlocked Keychain is rejecting, and both adds fail
            // alike. The 13 Simulator installs that hit #996's -34018 resolved
            // `failed`, which is reachable only when the local add failed too.
            // There, this costs one call on an already-failing path.
            //
            // On macOS the flag selects the BACKEND. `true` routes the item to
            // the data-protection Keychain, which requires an
            // `application-identifier` entitlement; without the flag the item
            // lands in the file-based login Keychain, which requires none. So
            // in an unentitled macOS process the synchronizable add fails with
            // -34018 while the local add succeeds — measured, and independent
            // of which one runs first — and this retry is the only reason the
            // session persists at all. That is exactly the process `swift
            // test` runs in, which is why KeychainTokenStorageTests' two
            // `synchronizable: true` round-trip cases pass on the macOS host
            // and are skipped in the iOS Simulator; deleting this branch turns
            // them red. `KeychainPlatformAsymmetryTests` in that same file
            // asserts the whole taxonomy, and asserts that the item left
            // behind is the one this retry wrote. iOS#1037 asks whether the
            // branch should survive; on this evidence it is not dead code.
            //
            // (issue #210)
            if synchronizable && status != errSecSuccess {
                query[kSecAttrSynchronizable as String] = false
                status = SecItemAdd(query as CFDictionary, nil)
            }
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

    // Internal (rather than private) so tests can verify the access-group
    // plumbing — Keychain access groups require an entitled signed host, so a
    // Swift Package unit-test bundle cannot exercise a full round-trip and
    // must introspect the query instead (issue #336).
    internal func baseQuery() -> [String: Any] {
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

    /// Attempts to load a session saved without the synchronizable flag.
    ///
    /// `save()` retries without `kSecAttrSynchronizable` when the synchronizable
    /// add fails, so such items do exist; this method finds them with a query
    /// that omits the attribute.
    ///
    /// It is belt-and-braces, not the thing that keeps those items reachable.
    /// `baseQuery()` uses `kSecAttrSynchronizableAny` when `synchronizable` is
    /// `true`, and that value does match non-synchronizable items — verified,
    /// not inferred — so `load()`'s primary read already finds anything this
    /// method could; its query is a strict subset, and it only runs after that
    /// read returned `errSecItemNotFound`. Worth knowing before citing this
    /// method as the reason a local-only item stays readable: the
    /// `kSecAttrSynchronizableAny` in `baseQuery()` is that reason. See
    /// iOS#1037.
    ///
    /// - Returns: The session if found, or `nil`.
    private func loadNonSynchronizable() -> AuthSession? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

        do {
            return try JSONDecoder.shared.decode(AuthSession.self, from: data)
        } catch {
            trackKeychainError(operation: .read, status: errSecDecode)
            return nil
        }
    }

    private func trackKeychainError(operation: KeychainOperation, status: OSStatus) {
        analytics.capture(RequestLineKeychainErrorEvent(
            operation: operation,
            osStatus: status
        ))
    }
}
