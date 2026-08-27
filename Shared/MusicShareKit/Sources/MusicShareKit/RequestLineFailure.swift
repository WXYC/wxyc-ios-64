//
//  RequestLineFailure.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 08/27/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Why a request did not reach the booth. The composer classifies; the view
/// renders — so the copy lives next to the layout that has to fit it, and the
/// cases stay assertable in tests without string matching.
public enum RequestLineFailure: Equatable, Sendable {
    /// Anonymous auth could not be established, so the request was never
    /// sent. ROM was not contacted. Dominant causes are transient: a 429
    /// from the sign-in limiter, or a Keychain miss on a cold launch.
    case authUnavailable

    /// The POST to request-o-matic did not complete.
    case boothUnreachable

    /// The booth answered, with a status we don't treat as success.
    case boothRejected(statusCode: Int)

    /// Classifies a ``RequestServiceError`` into the cause a listener should
    /// be told about. `403` never arrives here — `RequestService` returns
    /// without throwing on a shadow ban.
    public init(_ error: RequestServiceError) {
        switch error {
        case .authenticationFailed:
            self = .authUnavailable
        case .serverError(let statusCode):
            self = .boothRejected(statusCode: statusCode)
        case .invalidResponse, .encodingFailed, .networkError, .emptyMessage, .userBanned:
            self = .boothUnreachable
        }
    }

    /// The wire value for the `failureCause` property on the failed-send
    /// error report, so an auth-unavailable drop is separable from a
    /// booth-unreachable drop in PostHog without string-matching `error`.
    public var analyticsValue: String {
        switch self {
        case .authUnavailable: "authUnavailable"
        case .boothUnreachable: "boothUnreachable"
        case .boothRejected(let statusCode): "boothRejected(\(statusCode))"
        }
    }
}
