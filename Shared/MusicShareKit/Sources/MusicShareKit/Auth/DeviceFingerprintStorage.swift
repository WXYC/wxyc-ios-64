//
//  DeviceFingerprintStorage.swift
//  MusicShareKit
//
//  Stable per-device identifier persisted in iCloud Keychain.
//
//  Created by Jake Bromberg on 06/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Security

/// Storage for a stable per-device fingerprint.
///
/// The fingerprint is a UUIDv4 generated once per device (and synchronized
/// across the user's devices via iCloud Keychain when available). It persists
/// across app uninstalls so an abusive listener cannot evade a ban by
/// reinstalling the app on the same Apple ID.
public protocol DeviceFingerprintStorage: Sendable {

    /// Returns the device fingerprint, generating and persisting one if needed.
    ///
    /// First call generates a UUIDv4 and writes it to the Keychain. Subsequent
    /// calls (within the same process or across processes / launches) return
    /// the persisted value.
    ///
    /// - Throws: `AuthenticationError.keychainError` when both the read and the
    ///   subsequent add fail with an unrecoverable status. Calls do not throw
    ///   on a benign duplicate-item race (handled internally).
    func ensure() throws -> String
}

// MARK: - Keychain Operations Seam

/// Narrow seam over `SecItemCopyMatching` / `SecItemAdd` so unit tests can
/// drive the cross-process duplicate-item race deterministically without a
/// real Keychain (which requires an entitled signed host).
internal protocol KeychainOperations: Sendable {
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?)
    func add(_ attributes: CFDictionary) -> OSStatus
}

/// Production seam that forwards to the real Keychain.
internal struct DefaultKeychainOperations: KeychainOperations {
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        return (status, result as? Data)
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }
}

// MARK: - Keychain Implementation

/// Keychain-backed device fingerprint storage.
///
/// Uses an atomic add-or-reread loop (D3 in the iOS#351 plan) to close the
/// cross-process race where the main app and share extension first-launch
/// simultaneously: both observe an empty Keychain, both try to write, the
/// second one's `SecItemAdd` returns `errSecDuplicateItem`, and we reread to
/// pick up whichever value the Keychain daemon committed first.
public struct KeychainDeviceFingerprintStorage: DeviceFingerprintStorage {

    private let accessGroup: String?
    private let operations: any KeychainOperations
    private let service: String
    private let account: String

    public init(accessGroup: String?) {
        self.init(
            accessGroup: accessGroup,
            operations: DefaultKeychainOperations(),
            service: Self.defaultService,
            account: Self.defaultAccount
        )
    }

    /// Internal initializer used by tests to override the Keychain
    /// service+account so real-Keychain integration tests don't collide
    /// with (and wipe) the host app's production fingerprint when run on
    /// a developer's device or simulator.
    internal init(
        accessGroup: String?,
        operations: any KeychainOperations,
        service: String = KeychainDeviceFingerprintStorage.defaultService,
        account: String = KeychainDeviceFingerprintStorage.defaultAccount
    ) {
        self.accessGroup = accessGroup
        self.operations = operations
        self.service = service
        self.account = account
    }

    public func ensure() throws -> String {
        // Cap retries so an undocumented Keychain quirk that returns
        // errSecDuplicateItem on add AND errSecItemNotFound on the next read
        // cannot livelock us. Three iterations is a generous ceiling — in
        // practice the loop completes in one or two.
        for _ in 0..<3 {
            // 1. Read existing item.
            let readQuery = readQueryDictionary()
            let (readStatus, data) = operations.copyMatching(readQuery as CFDictionary)

            switch readStatus {
            case errSecSuccess:
                if let data, let fingerprint = String(data: data, encoding: .utf8),
                   !fingerprint.isEmpty {
                    return fingerprint
                }
                // Found item but data is unreadable — treat as decode error.
                throw AuthenticationError.keychainError(status: errSecDecode)

            case errSecItemNotFound:
                break  // Fall through to add.

            default:
                throw AuthenticationError.keychainError(status: readStatus)
            }

            // 2. Generate fresh fingerprint and try to add it.
            let candidate = UUID().uuidString
            let addStatus = addWithFallback(value: candidate)

            switch addStatus {
            case errSecSuccess:
                return candidate

            case errSecDuplicateItem:
                // Another process wrote first between our read and our add.
                // Loop back to read the value that did win.
                continue

            default:
                throw AuthenticationError.keychainError(status: addStatus)
            }
        }

        throw AuthenticationError.keychainError(status: errSecDuplicateItem)
    }

    // MARK: - Add Helper

    /// Attempts a synchronizable add first, falling back to local-only storage
    /// when iCloud Keychain is unavailable (simulators, devices without an
    /// iCloud account). Local persistence is better than no persistence — the
    /// fingerprint still survives a reinstall on the same device, defeating
    /// the most common ban-evasion attempt (see Risk 3 in the iOS#351 plan
    /// and the pattern established by `KeychainTokenStorage` for iOS#210).
    private func addWithFallback(value: String) -> OSStatus {
        let syncAttrs = addAttributesDictionary(value: value, synchronizable: true)
        let syncStatus = operations.add(syncAttrs as CFDictionary)
        if syncStatus == errSecSuccess || syncStatus == errSecDuplicateItem {
            return syncStatus
        }
        let localAttrs = addAttributesDictionary(value: value, synchronizable: false)
        return operations.add(localAttrs as CFDictionary)
    }

    // MARK: - Query Builders

    private func readQueryDictionary() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func addAttributesDictionary(value: String, synchronizable: Bool) -> [String: Any] {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if synchronizable {
            attributes[kSecAttrSynchronizable as String] = true
        }
        if let accessGroup {
            attributes[kSecAttrAccessGroup as String] = accessGroup
        }
        return attributes
    }

    // MARK: - Constants

    /// Production Keychain service identifier. Tests can override via the
    /// internal init to avoid colliding with the host app's real fingerprint.
    internal static let defaultService = "fm.wxyc.devicefingerprint"
    internal static let defaultAccount = "fingerprint"
}

// MARK: - In-Memory Implementation

/// Thread-safe in-memory fingerprint storage for tests.
public final class InMemoryDeviceFingerprintStorage: DeviceFingerprintStorage,
    @unchecked Sendable {

    /// If set, `ensure()` returns this exact value; otherwise a fresh UUIDv4
    /// is generated on the first call and reused on subsequent calls.
    public var stubFingerprint: String?

    /// Number of times `ensure()` was called.
    public private(set) var ensureCallCount: Int = 0

    /// If set, `ensure()` throws this error.
    public var stubError: Error?

    private var generated: String?
    private let lock = NSLock()

    public init() {}

    public func ensure() throws -> String {
        lock.lock()
        defer { lock.unlock() }

        ensureCallCount += 1

        if let stubError {
            throw stubError
        }

        if let stubFingerprint {
            return stubFingerprint
        }

        if let generated {
            return generated
        }

        let fresh = UUID().uuidString
        generated = fresh
        return fresh
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubFingerprint = nil
        stubError = nil
        generated = nil
        ensureCallCount = 0
    }
}
