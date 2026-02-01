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
public struct RequestLineAuthStartedEvent: RequestLineAnalyticsEvent {
    public let source: AuthTokenSource

    public var properties: [String: Any]? {
        ["source": source.rawValue]
    }

    public init(source: AuthTokenSource) {
        self.source = source
    }
}

/// Event captured when authentication completes.
public struct RequestLineAuthCompletedEvent: RequestLineAnalyticsEvent {
    public let source: AuthTokenSource
    public let durationMs: Double
    public let success: Bool

    public var properties: [String: Any]? {
        [
            "source": source.rawValue,
            "duration_ms": durationMs,
            "success": success
        ]
    }

    public init(source: AuthTokenSource, durationMs: Double, success: Bool) {
        self.source = source
        self.durationMs = durationMs
        self.success = success
    }
}

/// Phase of authentication where a failure occurred.
public enum AuthFailurePhase: String, Sendable {
    case keychain
    case network
    case parse
}

/// Event captured when authentication fails.
public struct RequestLineAuthFailedEvent: RequestLineAnalyticsEvent {
    public let error: String
    public let phase: AuthFailurePhase

    public var properties: [String: Any]? {
        [
            "error": error,
            "phase": phase.rawValue
        ]
    }

    public init(error: String, phase: AuthFailurePhase) {
        self.error = error
        self.phase = phase
    }
}

// MARK: - Request Events

/// Event captured when a request completes.
public struct RequestLineRequestCompletedEvent: RequestLineAnalyticsEvent {
    public let authenticated: Bool
    public let statusCode: Int
    public let durationMs: Double

    public var properties: [String: Any]? {
        [
            "authenticated": authenticated,
            "status_code": statusCode,
            "duration_ms": durationMs
        ]
    }

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
public struct RequestLineTokenRefreshedEvent: RequestLineAnalyticsEvent {
    public let reason: TokenRefreshReason
    public let success: Bool

    public var properties: [String: Any]? {
        [
            "reason": reason.rawValue,
            "success": success
        ]
    }

    public init(reason: TokenRefreshReason, success: Bool) {
        self.reason = reason
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
public struct RequestLineKeychainErrorEvent: RequestLineAnalyticsEvent {
    public let operation: KeychainOperation
    public let osStatus: Int32

    public var properties: [String: Any]? {
        [
            "operation": operation.rawValue,
            "os_status": osStatus
        ]
    }

    public init(operation: KeychainOperation, osStatus: Int32) {
        self.operation = operation
        self.osStatus = osStatus
    }
}

// MARK: - Ban Events

/// Event captured when a user is banned.
public struct RequestLineUserBannedEvent: RequestLineAnalyticsEvent {
    public let userId: String

    public var properties: [String: Any]? {
        ["user_id": userId]
    }

    public init(userId: String) {
        self.userId = userId
    }
}

// MARK: - Feature Flag Events

/// Source of a feature flag evaluation.
public enum FeatureFlagSource: String, Sendable {
    case flag
    case override
}

/// Event captured when the feature flag is evaluated.
public struct RequestLineFeatureFlagEvaluatedEvent: RequestLineAnalyticsEvent {
    public let enabled: Bool
    public let source: FeatureFlagSource

    public var properties: [String: Any]? {
        [
            "enabled": enabled,
            "source": source.rawValue
        ]
    }

    public init(enabled: Bool, source: FeatureFlagSource) {
        self.enabled = enabled
        self.source = source
    }
}
