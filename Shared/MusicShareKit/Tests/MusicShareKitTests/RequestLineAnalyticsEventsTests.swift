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

@Suite("RequestLineAnalytics event parity")
struct RequestLineAnalyticsEventsTests {

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
        arguments: authTokenSourceCases
    )
    func authCompletedEventProperties(_ fixture: (AuthTokenSource, String)) throws {
        let event = RequestLineAuthCompletedEvent(source: fixture.0, durationMs: 42.5, success: true)
        let props = try #require(event.properties)

        #expect(props["source"] as? String == fixture.1)
        #expect(props["duration_ms"] as? Double == 42.5)
        #expect(props["success"] as? Bool == true)
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

    @Test("RequestLineJWTExchangeEvent carries success and duration")
    func jwtExchangeEventProperties() throws {
        let event = RequestLineJWTExchangeEvent(success: true, durationMs: 123.0)
        let props = try #require(event.properties)

        #expect(props["success"] as? Bool == true)
        #expect(props["duration_ms"] as? Double == 123.0)
        #expect(props.count == 2)
        #expect(RequestLineJWTExchangeEvent.name == "request_line_jwt_exchange_event")
    }

    // MARK: - RequestLineRequestCompletedEvent

    @Test("RequestLineRequestCompletedEvent carries authenticated, status code, and duration")
    func requestCompletedEventProperties() throws {
        let event = RequestLineRequestCompletedEvent(authenticated: true, statusCode: 200, durationMs: 88.0)
        let props = try #require(event.properties)

        #expect(props["authenticated"] as? Bool == true)
        #expect(props["status_code"] as? Int == 200)
        #expect(props["duration_ms"] as? Double == 88.0)
        #expect(props.count == 3)
        #expect(RequestLineRequestCompletedEvent.name == "request_line_request_completed_event")
    }

    // MARK: - RequestLineTokenRefreshedEvent

    @Test(
        "RequestLineTokenRefreshedEvent carries the refresh reason's raw value and success",
        arguments: tokenRefreshReasonCases
    )
    func tokenRefreshedEventProperties(_ fixture: (TokenRefreshReason, String)) throws {
        let event = RequestLineTokenRefreshedEvent(reason: fixture.0, success: false)
        let props = try #require(event.properties)

        #expect(props["reason"] as? String == fixture.1)
        #expect(props["success"] as? Bool == false)
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

    // MARK: - RequestLineFeatureFlagEvaluatedEvent

    @Test(
        "RequestLineFeatureFlagEvaluatedEvent carries enabled and the source's raw value",
        arguments: featureFlagSourceCases
    )
    func featureFlagEvaluatedEventProperties(_ fixture: (FeatureFlagSource, String)) throws {
        let event = RequestLineFeatureFlagEvaluatedEvent(enabled: true, source: fixture.0)
        let props = try #require(event.properties)

        #expect(props["enabled"] as? Bool == true)
        #expect(props["source"] as? String == fixture.1)
        #expect(props.count == 2)
        #expect(RequestLineFeatureFlagEvaluatedEvent.name == "request_line_feature_flag_evaluated_event")
    }
}
