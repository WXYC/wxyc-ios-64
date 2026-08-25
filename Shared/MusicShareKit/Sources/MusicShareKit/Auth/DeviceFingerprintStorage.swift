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

// MARK: - Resolved Mode

/// How the device fingerprint came to be available on this launch.
///
/// Reported once per launch as `fingerprint_mode_resolved_event` (#998). Modes
/// and status codes are the entire permitted payload — the fingerprint value
/// itself is a stable per-device identifier and therefore a deanonymization
/// vector, and must never reach analytics.
public enum DeviceFingerprintMode: String, CaseIterable, Sendable {

    /// A value was already persisted and was read back; nothing was written.
    ///
    /// This is the steady state for every launch after the first, and it is
    /// deliberately NOT reported as `synchronizable` or `local`. The read query
    /// uses `kSecAttrSynchronizableAny` and does not request attributes back,
    /// so the read genuinely cannot tell which of the two the stored item is.
    /// Asking for the attribute would mean changing the read on the exact code
    /// path #996 is investigating, which would perturb the measurement this
    /// event exists to take. `existing` states the honest thing: present,
    /// sync-ness unknown.
    case existing

    /// No value was persisted, and a fresh one was written with
    /// `kSecAttrSynchronizable = true` — the ideal outcome. The item survives a
    /// reinstall and syncs across the Apple ID's devices.
    case synchronizable

    /// No value was persisted, the synchronizable write failed, and the
    /// local-only write succeeded. The item survives a reinstall on this device
    /// but does not sync. The accompanying `OSStatus` is the synchronizable
    /// write's failing status — the reason we are on the fallback.
    case local

    /// No fingerprint could be resolved at all. The `X-Device-Fingerprint`
    /// header is omitted from subsequent requests.
    case failed
}

/// The outcome of resolving the device fingerprint: the value, which branch
/// produced it, and the `OSStatus` that explains a non-ideal outcome.
public struct DeviceFingerprintResolution: Sendable {

    /// The resolved fingerprint. Never logged, never captured.
    public let value: String

    /// Which branch produced ``value``.
    public let mode: DeviceFingerprintMode

    /// The status that explains why this mode and not a better one:
    ///
    /// - ``DeviceFingerprintMode/existing`` and
    ///   ``DeviceFingerprintMode/synchronizable``: `errSecSuccess`. Nothing to
    ///   explain — the ideal path ran.
    /// - ``DeviceFingerprintMode/local``: the status the synchronizable add
    ///   failed with.
    ///
    /// A resolution never carries ``DeviceFingerprintMode/failed``; that mode
    /// is derived by the caller from a thrown error, whose status it reports
    /// instead.
    public let osStatus: OSStatus

    public init(value: String, mode: DeviceFingerprintMode, osStatus: OSStatus = errSecSuccess) {
        self.value = value
        self.mode = mode
        self.osStatus = osStatus
    }
}

// MARK: - Storage Protocol

/// Storage for a stable per-device fingerprint.
///
/// The fingerprint is a UUIDv4 generated once per device (and synchronized
/// across the user's devices via iCloud Keychain when available). It persists
/// across app uninstalls so an abusive listener cannot evade a ban by
/// reinstalling the app on the same Apple ID.
public protocol DeviceFingerprintStorage: Sendable {

    /// Returns the device fingerprint and how it was resolved, generating and
    /// persisting one if needed.
    ///
    /// First call generates a UUIDv4 and writes it to the Keychain. Subsequent
    /// calls (within the same process or across processes / launches) return
    /// the persisted value.
    ///
    /// The sole requirement, deliberately with no default implementation. A
    /// default would let a future conformer inherit a mode it never actually
    /// observed, and the entire point of #998 is that this subsystem must not
    /// be able to report something indistinguishable from silence.
    ///
    /// - Throws: `AuthenticationError.keychainError` when both the read and the
    ///   subsequent add fail with an unrecoverable status. Calls do not throw
    ///   on a benign duplicate-item race (handled internally).
    func resolve() throws -> DeviceFingerprintResolution
}

extension DeviceFingerprintStorage {

    /// The resolved fingerprint, discarding how it was resolved.
    ///
    /// Derived rather than a requirement: ``resolve()`` strictly subsumes it,
    /// so a conformer that implemented both could make the two disagree with
    /// nothing to catch it. The mode is the part a conformer can legitimately
    /// vary, and it stays dynamically dispatched.
    ///
    /// - Throws: the same errors as ``resolve()``, under the same conditions.
    public func ensure() throws -> String {
        try resolve().value
    }
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

    public func resolve() throws -> DeviceFingerprintResolution {
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
                    return DeviceFingerprintResolution(value: fingerprint, mode: .existing)
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
            let outcome = addWithFallback(value: candidate)

            switch outcome.status {
            case errSecSuccess:
                return DeviceFingerprintResolution(
                    value: candidate,
                    mode: outcome.mode,
                    osStatus: outcome.explanation
                )

            case errSecDuplicateItem:
                // Another process wrote first between our read and our add.
                // Loop back to read the value that did win.
                continue

            default:
                throw AuthenticationError.keychainError(status: outcome.status)
            }
        }

        throw AuthenticationError.keychainError(status: errSecDuplicateItem)
    }

    // MARK: - Add Helper

    /// Which add branch produced a status, and why.
    ///
    /// Exists only so `resolve()` can report a mode. `status` is exactly what
    /// `addWithFallback` returned before #998 widened its return type, and the
    /// two extra fields are derived from control flow that already ran — no
    /// Keychain call was added, moved, or re-gated to produce them.
    private struct AddOutcome {

        /// The status `resolve()` branches on. Unchanged semantics.
        let status: OSStatus

        /// The synchronizable add's failing status, or `nil` if it succeeded
        /// and we never fell back. This is the one bit that distinguishes the
        /// two branches, so `mode` and `explanation` derive from it rather
        /// than being assigned alongside it — `(.local, errSecSuccess)` and
        /// `(.synchronizable, -34018)` are not representable.
        let syncFailure: OSStatus?

        /// The branch that produced ``status``.
        var mode: DeviceFingerprintMode { syncFailure == nil ? .synchronizable : .local }

        /// Why we are on that branch: the synchronizable add's failing status
        /// when we fell back to local-only, `errSecSuccess` otherwise.
        var explanation: OSStatus { syncFailure ?? errSecSuccess }
    }

    /// Attempts a synchronizable add first, falling back to local-only storage
    /// when iCloud Keychain is unavailable (simulators, devices without an
    /// iCloud account). Local persistence is better than no persistence — the
    /// fingerprint still survives a reinstall on the same device, defeating
    /// the most common ban-evasion attempt (see Risk 3 in the iOS#351 plan
    /// and the pattern established by `KeychainTokenStorage` for iOS#210).
    private func addWithFallback(value: String) -> AddOutcome {
        let syncAttrs = addAttributesDictionary(value: value, synchronizable: true)
        let syncStatus = operations.add(syncAttrs as CFDictionary)
        if syncStatus == errSecSuccess || syncStatus == errSecDuplicateItem {
            return AddOutcome(status: syncStatus, syncFailure: nil)
        }
        let localAttrs = addAttributesDictionary(value: value, synchronizable: false)
        let localStatus = operations.add(localAttrs as CFDictionary)
        // `syncFailure` is `syncStatus`, not `localStatus`: the local add's own
        // status is what `resolve()` branches on, but the reason this device is
        // on the fallback at all is the status the synchronizable add failed
        // with. That is the value #996 needs — if -34018 reaches this path,
        // this is where it becomes visible.
        return AddOutcome(status: localStatus, syncFailure: syncStatus)
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

    /// Number of times the value was resolved, through either `ensure()` or
    /// ``resolve()``.
    public private(set) var ensureCallCount: Int = 0

    /// If set, `ensure()` throws this error.
    public var stubError: Error?

    /// The mode `resolve()` reports. Defaults to
    /// ``DeviceFingerprintMode/existing`` because that is what this double
    /// models: a value that is simply already there, with no Keychain write
    /// attempted and therefore nothing knowable about sync-ness.
    public var stubMode: DeviceFingerprintMode = .existing

    private var generated: String?
    private let lock = NSLock()

    public init() {}

    /// The protocol's sole requirement, so this is where the stub logic lives.
    /// `ensure()` reaches it through the protocol extension, which is what
    /// keeps `ensureCallCount` accurate from either entry point.
    public func resolve() throws -> DeviceFingerprintResolution {
        lock.lock()
        defer { lock.unlock() }

        ensureCallCount += 1

        if let stubError {
            throw stubError
        }

        let value: String
        if let stubFingerprint {
            value = stubFingerprint
        } else if let generated {
            value = generated
        } else {
            let fresh = UUID().uuidString
            generated = fresh
            value = fresh
        }

        return DeviceFingerprintResolution(value: value, mode: stubMode)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubFingerprint = nil
        stubError = nil
        stubMode = .existing
        generated = nil
        ensureCallCount = 0
    }
}
