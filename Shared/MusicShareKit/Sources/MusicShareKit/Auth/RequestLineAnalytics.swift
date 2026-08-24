//
//  RequestLineAnalytics.swift
//  MusicShareKit
//
//  Structured analytics events for request line authentication.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Foundation

// MARK: - Marker Protocol

/// Marker protocol for all request line analytics events.
public protocol RequestLineAnalyticsEvent: AnalyticsEvent {}

// MARK: - Auth Token Source

/// The source from which an auth token was retrieved.
public enum AuthTokenSource: String, CaseIterable, Sendable {
    case cache
    case keychain
    case network
}

// MARK: - Auth Events

/// Event captured when authentication starts.
///
/// `source` is stored as a `String` (its `AuthTokenSource.rawValue`) rather
/// than the enum itself: `@AnalyticsEvent` emits stored properties verbatim
/// into the `properties` dict without calling `.rawValue` on an enum (see
/// `FetchPlaylistEvent` in the Playlist package for the same pattern), so the
/// stored type has to already be the wire value.
@AnalyticsEvent
public struct RequestLineAuthStartedEvent: RequestLineAnalyticsEvent {
    public let source: String

    public init(source: AuthTokenSource) {
        self.source = source.rawValue
    }
}

/// Event captured when authentication completes.
///
/// `source` is stored as a `String` for the same macro-verbatim reason
/// documented on `RequestLineAuthStartedEvent`.
@AnalyticsEvent
public struct RequestLineAuthCompletedEvent: RequestLineAnalyticsEvent {
    public let source: String
    public let durationMs: Double
    public let success: Bool

    public init(source: AuthTokenSource, durationMs: Double, success: Bool) {
        self.source = source.rawValue
        self.durationMs = durationMs
        self.success = success
    }
}

/// Phase of authentication where a failure occurred.
public enum AuthFailurePhase: String, CaseIterable, Sendable {
    case keychain
    case network
    case parse
    case jwtExchange
}

/// Event captured when authentication fails.
///
/// `phase` is stored as a `String` for the same macro-verbatim reason
/// documented on `RequestLineAuthStartedEvent`.
@AnalyticsEvent
public struct RequestLineAuthFailedEvent: RequestLineAnalyticsEvent {
    public let error: String
    public let phase: String

    public init(error: String, phase: AuthFailurePhase) {
        self.error = error
        self.phase = phase.rawValue
    }
}

/// Event captured when a JWT exchange completes.
@AnalyticsEvent
public struct RequestLineJWTExchangeEvent: RequestLineAnalyticsEvent {
    public let success: Bool
    public let durationMs: Double

    public init(success: Bool, durationMs: Double) {
        self.success = success
        self.durationMs = durationMs
    }
}

// MARK: - Request Events

/// Event captured when a request completes.
@AnalyticsEvent
public struct RequestLineRequestCompletedEvent: RequestLineAnalyticsEvent {
    public let authenticated: Bool
    public let statusCode: Int
    public let durationMs: Double

    public init(authenticated: Bool, statusCode: Int, durationMs: Double) {
        self.authenticated = authenticated
        self.statusCode = statusCode
        self.durationMs = durationMs
    }
}

// MARK: - Token Events

/// Reason why a token was refreshed.
public enum TokenRefreshReason: String, CaseIterable, Sendable {
    case unauthorized = "401"
    case expired
}

/// Event captured when a token is refreshed.
///
/// `reason` is stored as a `String` for the same macro-verbatim reason
/// documented on `RequestLineAuthStartedEvent`.
@AnalyticsEvent
public struct RequestLineTokenRefreshedEvent: RequestLineAnalyticsEvent {
    public let reason: String
    public let success: Bool

    public init(reason: TokenRefreshReason, success: Bool) {
        self.reason = reason.rawValue
        self.success = success
    }
}

// MARK: - Keychain Events

/// Keychain operation type.
public enum KeychainOperation: String, CaseIterable, Sendable {
    case read
    case write
    case delete
}

/// Event captured when a Keychain error occurs.
///
/// `operation` is stored as a `String` for the same macro-verbatim reason
/// documented on `RequestLineAuthStartedEvent`.
@AnalyticsEvent
public struct RequestLineKeychainErrorEvent: RequestLineAnalyticsEvent {
    public let operation: String
    public let osStatus: Int32

    public init(operation: KeychainOperation, osStatus: Int32) {
        self.operation = operation.rawValue
        self.osStatus = osStatus
    }
}

// MARK: - Ban Events

/// Event captured when a user is banned.
@AnalyticsEvent
public struct RequestLineUserBannedEvent: RequestLineAnalyticsEvent {
    public let userId: String

    public init(userId: String) {
        self.userId = userId
    }
}

// MARK: - Device Fingerprint Events

/// Event captured when the device fingerprint cannot be initialized at
/// `MusicShareKit.configure(...)` time (e.g., Keychain locked pre-first-unlock,
/// missing entitlement, iCloud Keychain in an inconsistent state).
///
/// A failure here causes the `X-Device-Fingerprint` header to be omitted from
/// subsequent requests. ROM proceeds-as-unauth for those requests, so the
/// listener can still send a request — the only user-visible effect is that
/// the ban-evasion vector temporarily opens for that user.
@AnalyticsEvent
public struct DeviceFingerprintInitFailedEvent: RequestLineAnalyticsEvent {
    public let error: String

    public init(error: String) {
        self.error = error
    }
}

/// Event captured once per launch, from `MusicShareKit.configure(...)`, stating
/// how the device fingerprint resolved (#998).
///
/// **Emitted on success and on failure alike, and that is the whole point.**
/// `DeviceFingerprintInitFailedEvent` above is failure-only, and a failure-only
/// metric reads exactly like a metric that stopped reporting — its 0 rows in 30
/// days could mean "the Keychain is fine" or "nothing is being captured at
/// all", and there is no way to tell from the data. During the 2026-08-04
/// PostHog quota exhaustion the org spent two weeks reading the second as the
/// first. This event's absence is therefore always a defect, never good news.
///
/// **Once per launch, not once per operation.** The PostHog org is on the free
/// tier at its six-project limit; `capture()` is a billing decision. One
/// summary event per launch is the budget, which is why the
/// `MusicShareKit.deviceFingerprint` accessor's inline retry deliberately does
/// not emit a second one.
///
/// The fingerprint **value** never appears here. It is a stable per-device
/// identifier and a deanonymization vector; modes and status codes are the
/// entire permitted payload.
///
/// `mode` is stored as a `String` for the same macro-verbatim reason documented
/// on `RequestLineAuthStartedEvent`.
@AnalyticsEvent
public struct FingerprintModeResolvedEvent: RequestLineAnalyticsEvent {

    /// A ``DeviceFingerprintMode`` raw value.
    public let mode: String

    /// The status that explains this mode: the synchronizable add's failing
    /// status on `local`, the thrown status on `failed`, and `errSecSuccess`
    /// on `existing` and `synchronizable`, where nothing needs explaining.
    ///
    /// Non-optional on purpose. Every value emitted is a real `OSStatus`
    /// returned by an operation that actually ran, and an always-present
    /// numeric property is what PostHog needs to break the launch population
    /// down by status without a missing-key branch.
    public let osStatus: Int32

    /// How many times `MusicShareKit.deviceFingerprint` was read before
    /// `configure(...)` ran in this process. That path has no analytics service
    /// to report to at the moment it happens — the configuration is where the
    /// analytics service lives — so its total rides here instead of vanishing.
    /// Anything above 0 means a caller is reaching the fingerprint too early
    /// and getting `nil`.
    public let prematureAccessCount: Int

    public init(mode: DeviceFingerprintMode, osStatus: OSStatus, prematureAccessCount: Int) {
        self.mode = mode.rawValue
        self.osStatus = osStatus
        self.prematureAccessCount = prematureAccessCount
    }
}

// MARK: - Feature Flag Events

/// Source of a feature flag evaluation.
public enum FeatureFlagSource: String, CaseIterable, Sendable {
    case flag
    case override
}

/// Event captured when the feature flag is evaluated.
///
/// `source` is stored as a `String` for the same macro-verbatim reason
/// documented on `RequestLineAuthStartedEvent`.
@AnalyticsEvent
public struct RequestLineFeatureFlagEvaluatedEvent: RequestLineAnalyticsEvent {
    public let enabled: Bool
    public let source: String

    public init(enabled: Bool, source: FeatureFlagSource) {
        self.enabled = enabled
        self.source = source.rawValue
    }
}
