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
public enum AuthTokenSource: String, Sendable {
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
public enum AuthFailurePhase: String, Sendable {
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
public enum TokenRefreshReason: String, Sendable {
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
public enum KeychainOperation: String, Sendable {
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

// MARK: - Feature Flag Events

/// Source of a feature flag evaluation.
public enum FeatureFlagSource: String, Sendable {
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
