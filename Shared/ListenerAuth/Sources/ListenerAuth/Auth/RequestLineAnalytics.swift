//
//  RequestLineAnalytics.swift
//  ListenerAuth
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

// MARK: - Auth Events

/// How an auth resolution obtained its JWT — `performRefresh`'s branches
/// 3a/3b/3c, invisible before #1067 (3b and 3c both read `source: "network"`).
///
/// This is the summary event's only resolution dimension. The old
/// `AuthTokenSource` (`cache`/`keychain`/`network`) is gone with the four
/// events that carried it: `source` was a total function of this outcome
/// (`.keychainHit` → keychain, everything else → network), so shipping both
/// meant two properties that could contradict each other and none that said
/// anything the other didn't. "Network vs Keychain" is `outcome !=
/// keychain_hit`; the reverse split is not recoverable from `source`, which
/// is why the finer of the two is the one that survives. `cache` has no
/// successor at all — that path stopped emitting entirely.
public enum AuthResolutionOutcome: String, CaseIterable, Sendable {
    /// 3a: a Keychain-persisted session with a still-fresh JWT — no network call.
    case keychainHit = "keychain_hit"
    /// 3b: the stored session token was still valid; a new JWT was minted via `/auth/token`.
    case tokenRefresh = "token_refresh"
    /// 3c: no usable session (or the server rejected it); a fresh anonymous sign-in ran.
    case freshSignIn = "fresh_sign_in"
}

/// Summary event emitted once per real auth resolution, collapsing the
/// four-event cascade #1067 found responsible for ~41k events/12d
/// (`RequestLineAuthStartedEvent`, `RequestLineJWTExchangeEvent`,
/// `FingerprintModeResolvedEvent`, `RequestLineAuthCompletedEvent`, all now
/// removed) into properties on one row.
///
/// Not emitted on the in-memory cache fast path (deleted outright by #1067's
/// first PR — a pure in-memory read is not a resolution) or on failure:
/// `RequestLineAuthFailedEvent`/`RequestLineKeychainErrorEvent` remain the
/// unchanged failure-path signal (#996/#1002 load-bearing).
///
/// Hand-written rather than `@AnalyticsEvent`-generated so `jwtDurationMs`
/// can be omitted on `.keychainHit` (no exchange happens there) instead of
/// landing as a boxed-nil `Any` — see `ErrorEvent`/`PlaybackStartedEvent` for
/// the same pattern. Because `properties` is spelled out here rather than
/// macro-derived, the enum-typed properties are stored as their enums and
/// converted at the boundary; the rawValue-stored convention documented on
/// ``RequestLineAuthFailedEvent`` exists only to work around the macro
/// copying stored properties verbatim, and does not apply to this type.
///
/// `durationMs`/`jwtDurationMs` are each capped at `AuthenticationService`'s
/// 60,000 ms clamp before reaching here — the #1067 investigation found
/// suspend-mid-`await` durations up to 8,452,908 ms (2.35 h), a backgrounding
/// artifact rather than a slow server. `durationClamped` is true whenever
/// either raw measurement exceeded the cap.
public struct RequestLineAuthResolvedEvent: RequestLineAnalyticsEvent {
    public static let name = "request_line_auth_resolved"

    /// Which branch of `performRefresh` served the JWT.
    public let outcome: AuthResolutionOutcome

    /// How the device fingerprint resolved at `configure(...)` time. A
    /// per-launch fact repeated on every resolution of that launch, which is
    /// the price of retiring the dedicated per-launch event (#998) that
    /// carried it.
    ///
    /// One property of the retired event does not survive that move, and it
    /// is worth knowing before reading a dashboard: `fingerprint_mode` was
    /// emitted unconditionally, exactly once per launch, so its count *was*
    /// the launch count and a drop to zero could only mean the pipeline had
    /// stopped. Here it rides a resolution, and a launch that resolves nothing
    /// (JWT stays fresh, every call a cache hit) contributes no row — so a
    /// fall in volume now has two explanations, "fewer resolutions" and
    /// "nothing is reporting", exactly the ambiguity that hid #996 for two
    /// weeks. Read this field as a *distribution* over resolutions, never as a
    /// population count, and use a separate always-on signal if you need to
    /// know the pipeline is alive.
    public let fingerprintMode: DeviceFingerprintMode

    /// How many `MusicShareKit.deviceFingerprint` reads landed before
    /// `configure(...)` ran in this process, snapshotted at the same moment
    /// as ``fingerprintMode``. Inherited from the retired
    /// `fingerprint_mode_resolved_event`'s `premature_access_count`, under the
    /// same wire key so the two eras answer one query. Anything above 0 means
    /// a caller is reaching the fingerprint too early and getting `nil`
    /// (#998); that path has no analytics service to report to at the moment
    /// it happens, so this is its only route to PostHog.
    ///
    /// The third property of the retired event, `os_status`, deliberately has
    /// no successor here: on the `.failed` branch the status is already
    /// carried by the `DeviceFingerprintInitFailedEvent` captured alongside it
    /// (`AuthenticationError.keychainError`'s description is literally
    /// `"Keychain error: <status>"`), and on `.local` it is unreachable
    /// outside an unentitled macOS test process — see
    /// ``DeviceFingerprintMode/local``. Folding in the count but not the
    /// status is the line between "this signal has no other home" and "this
    /// signal already has one".
    public let prematureAccessCount: Int

    /// Duration of the `/auth/token` or `/sign-in/anonymous` JWT exchange,
    /// or `nil` on `.keychainHit`, where no exchange runs. Milliseconds — the
    /// `_ms` suffix is load-bearing in a PostHog project shared with Android,
    /// where the unsuffixed `duration` is seconds on `pause`.
    public let jwtDurationMs: Double?

    /// Total resolution time in milliseconds, same suffix rule as
    /// ``jwtDurationMs``.
    public let durationMs: Double

    /// True when either raw measurement hit the 60 s cap, i.e. the numbers
    /// above are floors rather than measurements.
    public let durationClamped: Bool

    public var properties: [String: Any]? {
        var props: [String: Any] = [
            "outcome": outcome.rawValue,
            "fingerprint_mode": fingerprintMode.rawValue,
            "premature_access_count": prematureAccessCount,
            "duration_ms": durationMs,
            "duration_clamped": durationClamped,
        ]
        if let jwtDurationMs { props["jwt_duration_ms"] = jwtDurationMs }
        return props
    }

    public init(
        outcome: AuthResolutionOutcome,
        fingerprintMode: DeviceFingerprintMode,
        prematureAccessCount: Int,
        jwtDurationMs: Double?,
        durationMs: Double,
        durationClamped: Bool
    ) {
        self.outcome = outcome
        self.fingerprintMode = fingerprintMode
        self.prematureAccessCount = prematureAccessCount
        self.jwtDurationMs = jwtDurationMs
        self.durationMs = durationMs
        self.durationClamped = durationClamped
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
/// `phase` is stored as a `String` (its `AuthFailurePhase.rawValue`) rather
/// than the enum itself: `@AnalyticsEvent` emits stored properties verbatim
/// into the `properties` dict without calling `.rawValue` on an enum (see
/// `FetchPlaylistEvent` in the Playlist package for the same pattern), so the
/// stored type has to already be the wire value. Every other enum-backed
/// property on an `@AnalyticsEvent` type in this file follows the same rule.
/// ``RequestLineAuthResolvedEvent`` is the one exception and is allowed to be:
/// it writes its own `properties`, so it stores the enums and calls
/// `.rawValue` there.
@AnalyticsEvent
public struct RequestLineAuthFailedEvent: RequestLineAnalyticsEvent {
    public let error: String
    public let phase: String

    public init(error: String, phase: AuthFailurePhase) {
        self.error = error
        self.phase = phase.rawValue
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
/// documented on `RequestLineAuthFailedEvent`.
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
/// documented on `RequestLineAuthFailedEvent`.
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
public enum FeatureFlagSource: String, CaseIterable, Sendable {
    case flag
    case override
    /// No `FeatureFlagProvider` was configured, so the flag could not be
    /// evaluated at all. Distinguishes "the app was never wired for feature
    /// flags" from "the flag evaluated false" — see
    /// `RequestLineAuthFeature.isEnabled(featureFlagProvider:defaults:analytics:)`'s
    /// step 3, the only capture site for this case.
    case unwired
}

/// Event captured when the feature flag is evaluated.
///
/// `source` is stored as a `String` for the same macro-verbatim reason
/// documented on `RequestLineAuthFailedEvent`.
@AnalyticsEvent
public struct RequestLineFeatureFlagEvaluatedEvent: RequestLineAnalyticsEvent {
    public let enabled: Bool
    public let source: String

    public init(enabled: Bool, source: FeatureFlagSource) {
        self.enabled = enabled
        self.source = source.rawValue
    }
}
