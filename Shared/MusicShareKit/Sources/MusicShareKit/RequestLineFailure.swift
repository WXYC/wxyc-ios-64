//
//  RequestLineFailure.swift
//  MusicShareKit
//
//  The cause-carrying classification of a Request Line send failure. The
//  composer classifies an error into one of these cases; the sheet in the
//  app target owns the copy, so the cases stay assertable in tests without
//  matching rendered strings.
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

    /// The POST to request-o-matic did not complete, or completed with a
    /// status that isn't a more specific story. This also covers a `403`:
    /// on the unauthenticated path (the whole install base today) ROM's
    /// shadow-ban response is a 403 with no JWT at all, so a banned listener
    /// reaches this the same way an unbanned one does on a real outage —
    /// folding it in here keeps the two indistinguishable rather than
    /// handing the ban away in the copy.
    case boothUnreachable

    /// The booth answered, with a status we don't treat as success.
    case boothRejected(statusCode: Int)

    /// Classifies an error into the cause a listener should be told about.
    /// Anything that isn't a ``RequestServiceError`` defaults to
    /// ``boothUnreachable``, folding what used to be a `?? .boothUnreachable`
    /// at the call site into the type itself.
    init(_ error: any Error) {
        guard let serviceError = error as? RequestServiceError else {
            self = .boothUnreachable
            return
        }
        switch serviceError {
        case .authenticationFailed:
            self = .authUnavailable
        case .serverError(let statusCode):
            self = statusCode == 403 ? .boothUnreachable : .boothRejected(statusCode: statusCode)
        case .invalidResponse, .encodingFailed, .networkError, .emptyMessage, .userBanned:
            self = .boothUnreachable
        }
    }

    /// The `failure_cause` wire value: the bare case name, with no
    /// associated value folded in — so a PostHog breakdown on it stays one
    /// series instead of fragmenting per HTTP status. A status code that's
    /// wanted alongside it rides under its own key instead.
    var analyticsName: String {
        switch self {
        case .authUnavailable: "authUnavailable"
        case .boothUnreachable: "boothUnreachable"
        case .boothRejected: "boothRejected"
        }
    }
}
