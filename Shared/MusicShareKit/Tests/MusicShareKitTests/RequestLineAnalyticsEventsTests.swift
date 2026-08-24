//
//  RequestLineAnalyticsEventsTests.swift
//  MusicShareKit
//
//  Parity coverage for RequestLineAnalytics.swift's ten events (#763): pins
//  each event's `name` and `properties` dict to the exact values the
//  hand-written conformances produced before the `@AnalyticsEvent` macro
//  adoption, so the macro's snake_case name/key derivation and (for the
//  enum-typed properties) the rawValue-backed storage can never silently
//  drift from what PostHog actually recorded pre-migration.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Security
import Testing
@testable import MusicShareKit

// MARK: - Enum case / expected raw-value fixtures

/// `(case, expected rawValue)` pairs. Expected values are hardcoded literals
/// rather than `case.rawValue` so the test actually pins the wire value —
/// deriving the expectation from `.rawValue` would make the assertion a
/// tautology against the very enum it's supposed to guard.
private let authTokenSourceCases: [(AuthTokenSource, String)] = [
    (.cache, "cache"),
    (.keychain, "keychain"),
    (.network, "network"),
]

private let authFailurePhaseCases: [(AuthFailurePhase, String)] = [
    (.keychain, "keychain"),
    (.network, "network"),
    (.parse, "parse"),
    (.jwtExchange, "jwtExchange"),
]

private let tokenRefreshReasonCases: [(TokenRefreshReason, String)] = [
    (.unauthorized, "401"),
    (.expired, "expired"),
]

private let keychainOperationCases: [(KeychainOperation, String)] = [
    (.read, "read"),
    (.write, "write"),
    (.delete, "delete"),
]

private let featureFlagSourceCases: [(FeatureFlagSource, String)] = [
    (.flag, "flag"),
    (.override, "override"),
]

private let deviceFingerprintModeCases: [(DeviceFingerprintMode, String)] = [
    (.existing, "existing"),
    (.synchronizable, "synchronizable"),
    (.local, "local"),
    (.failed, "failed"),
]

/// Every `Bool` property is exercised at both polarities. Asserting only the
/// `true` case would pass even if the macro emitted a literal instead of
/// reading the stored property, or if an init dropped the assignment.
private let bothPolarities: [Bool] = [true, false]

@Suite("RequestLineAnalytics event parity")
struct RequestLineAnalyticsEventsTests {

    // MARK: - Fixture exhaustiveness

    /// The fixture arrays above are hand-enumerated, so without this guard a
    /// newly added enum case ships an unpinned wire value to PostHog while
    /// every existing assertion still passes. Pinning each array against
    /// `allCases` makes them self-maintaining: adding a case fails here until
    /// its expected raw value is written down.
    @Test("Every enum case appears in its parity fixture array")
    func fixtureArraysCoverEveryCase() {
        #expect(Set(authTokenSourceCases.map(\.0)) == Set(AuthTokenSource.allCases))
        #expect(Set(authFailurePhaseCases.map(\.0)) == Set(AuthFailurePhase.allCases))
        #expect(Set(tokenRefreshReasonCases.map(\.0)) == Set(TokenRefreshReason.allCases))
        #expect(Set(keychainOperationCases.map(\.0)) == Set(KeychainOperation.allCases))
        #expect(Set(featureFlagSourceCases.map(\.0)) == Set(FeatureFlagSource.allCases))
        #expect(Set(deviceFingerprintModeCases.map(\.0)) == Set(DeviceFingerprintMode.allCases))
    }

    // MARK: - RequestLineAuthStartedEvent

    @Test(
        "RequestLineAuthStartedEvent carries the token source's raw value",
        arguments: authTokenSourceCases
    )
    func authStartedEventProperties(_ fixture: (AuthTokenSource, String)) throws {
        let event = RequestLineAuthStartedEvent(source: fixture.0)
        let props = try #require(event.properties)

        #expect(props["source"] as? String == fixture.1)
        #expect(props.count == 1)
        #expect(RequestLineAuthStartedEvent.name == "request_line_auth_started_event")
    }

    // MARK: - RequestLineAuthCompletedEvent

    @Test(
        "RequestLineAuthCompletedEvent carries source, duration, and success",
        arguments: authTokenSourceCases, bothPolarities
    )
    func authCompletedEventProperties(_ fixture: (AuthTokenSource, String), _ success: Bool) throws {
        let event = RequestLineAuthCompletedEvent(source: fixture.0, durationMs: 42.5, success: success)
        let props = try #require(event.properties)

        #expect(props["source"] as? String == fixture.1)
        #expect(props["duration_ms"] as? Double == 42.5)
        #expect(props["success"] as? Bool == success)
        #expect(props.count == 3)
        #expect(RequestLineAuthCompletedEvent.name == "request_line_auth_completed_event")
    }

    // MARK: - RequestLineAuthFailedEvent

    @Test(
        "RequestLineAuthFailedEvent carries the error string and the failure phase's raw value",
        arguments: authFailurePhaseCases
    )
    func authFailedEventProperties(_ fixture: (AuthFailurePhase, String)) throws {
        let event = RequestLineAuthFailedEvent(error: "network unreachable", phase: fixture.0)
        let props = try #require(event.properties)

        #expect(props["error"] as? String == "network unreachable")
        #expect(props["phase"] as? String == fixture.1)
        #expect(props.count == 2)
        #expect(RequestLineAuthFailedEvent.name == "request_line_auth_failed_event")
    }

    // MARK: - RequestLineJWTExchangeEvent

    @Test("RequestLineJWTExchangeEvent carries success and duration", arguments: bothPolarities)
    func jwtExchangeEventProperties(_ success: Bool) throws {
        let event = RequestLineJWTExchangeEvent(success: success, durationMs: 123.0)
        let props = try #require(event.properties)

        #expect(props["success"] as? Bool == success)
        #expect(props["duration_ms"] as? Double == 123.0)
        #expect(props.count == 2)
        #expect(RequestLineJWTExchangeEvent.name == "request_line_jwt_exchange_event")
    }

    // MARK: - RequestLineRequestCompletedEvent

    @Test(
        "RequestLineRequestCompletedEvent carries authenticated, status code, and duration",
        arguments: bothPolarities
    )
    func requestCompletedEventProperties(_ authenticated: Bool) throws {
        let event = RequestLineRequestCompletedEvent(authenticated: authenticated, statusCode: 200, durationMs: 88.0)
        let props = try #require(event.properties)

        #expect(props["authenticated"] as? Bool == authenticated)
        #expect(props["status_code"] as? Int == 200)
        #expect(props["duration_ms"] as? Double == 88.0)
        #expect(props.count == 3)
        #expect(RequestLineRequestCompletedEvent.name == "request_line_request_completed_event")
    }

    // MARK: - RequestLineTokenRefreshedEvent

    @Test(
        "RequestLineTokenRefreshedEvent carries the refresh reason's raw value and success",
        arguments: tokenRefreshReasonCases, bothPolarities
    )
    func tokenRefreshedEventProperties(_ fixture: (TokenRefreshReason, String), _ success: Bool) throws {
        let event = RequestLineTokenRefreshedEvent(reason: fixture.0, success: success)
        let props = try #require(event.properties)

        #expect(props["reason"] as? String == fixture.1)
        #expect(props["success"] as? Bool == success)
        #expect(props.count == 2)
        #expect(RequestLineTokenRefreshedEvent.name == "request_line_token_refreshed_event")
    }

    // MARK: - RequestLineKeychainErrorEvent

    @Test(
        "RequestLineKeychainErrorEvent carries the operation's raw value and the OSStatus",
        arguments: keychainOperationCases
    )
    func keychainErrorEventProperties(_ fixture: (KeychainOperation, String)) throws {
        let event = RequestLineKeychainErrorEvent(operation: fixture.0, osStatus: -25300)
        let props = try #require(event.properties)

        #expect(props["operation"] as? String == fixture.1)
        #expect(props["os_status"] as? Int32 == -25300)
        #expect(props.count == 2)
        #expect(RequestLineKeychainErrorEvent.name == "request_line_keychain_error_event")
    }

    // MARK: - RequestLineUserBannedEvent

    @Test("RequestLineUserBannedEvent carries the user id")
    func userBannedEventProperties() throws {
        let event = RequestLineUserBannedEvent(userId: "listener-42")
        let props = try #require(event.properties)

        #expect(props["user_id"] as? String == "listener-42")
        #expect(props.count == 1)
        #expect(RequestLineUserBannedEvent.name == "request_line_user_banned_event")
    }

    // MARK: - DeviceFingerprintInitFailedEvent

    @Test("DeviceFingerprintInitFailedEvent carries the error string")
    func deviceFingerprintInitFailedEventProperties() throws {
        let event = DeviceFingerprintInitFailedEvent(error: "errSecInteractionNotAllowed")
        let props = try #require(event.properties)

        #expect(props["error"] as? String == "errSecInteractionNotAllowed")
        #expect(props.count == 1)
        #expect(DeviceFingerprintInitFailedEvent.name == "device_fingerprint_init_failed_event")
    }

    // MARK: - FingerprintModeResolvedEvent

    @Test(
        "FingerprintModeResolvedEvent carries the mode's raw value, the OSStatus, and the premature-access count",
        arguments: deviceFingerprintModeCases
    )
    func fingerprintModeResolvedEventProperties(_ fixture: (DeviceFingerprintMode, String)) throws {
        let event = FingerprintModeResolvedEvent(
            mode: fixture.0,
            osStatus: errSecMissingEntitlement,
            prematureAccessCount: 7
        )
        let props = try #require(event.properties)

        #expect(props["mode"] as? String == fixture.1)
        #expect(props["os_status"] as? Int32 == -34018)
        #expect(props["premature_access_count"] as? Int == 7)
        #expect(props.count == 3)
        #expect(FingerprintModeResolvedEvent.name == "fingerprint_mode_resolved_event")
    }

    /// The event must never carry anything that identifies the device. The
    /// fingerprint is a stable per-device UUID and therefore a deanonymization
    /// vector; modes and status codes are the entire permitted payload.
    @Test(
        "FingerprintModeResolvedEvent's payload carries no UUID-shaped value",
        arguments: deviceFingerprintModeCases
    )
    func fingerprintModeResolvedEventOmitsTheFingerprint(
        _ fixture: (DeviceFingerprintMode, String)
    ) throws {
        let event = FingerprintModeResolvedEvent(
            mode: fixture.0,
            osStatus: errSecSuccess,
            prematureAccessCount: 0
        )
        let props = try #require(event.properties)

        let strings = props.values.compactMap { $0 as? String }
        #expect(strings.allSatisfy { UUID(uuidString: $0) == nil })
    }

    // MARK: - RequestLineFeatureFlagEvaluatedEvent

    @Test(
        "RequestLineFeatureFlagEvaluatedEvent carries enabled and the source's raw value",
        arguments: featureFlagSourceCases, bothPolarities
    )
    func featureFlagEvaluatedEventProperties(_ fixture: (FeatureFlagSource, String), _ enabled: Bool) throws {
        let event = RequestLineFeatureFlagEvaluatedEvent(enabled: enabled, source: fixture.0)
        let props = try #require(event.properties)

        #expect(props["enabled"] as? Bool == enabled)
        #expect(props["source"] as? String == fixture.1)
        #expect(props.count == 2)
        #expect(RequestLineFeatureFlagEvaluatedEvent.name == "request_line_feature_flag_evaluated_event")
    }
}
