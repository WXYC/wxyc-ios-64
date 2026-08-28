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
///
/// ## Why there is no rejected case
///
/// There was one, and it rendered "the booth turned that one down — try
/// rewording your request." Nothing in the system can produce that outcome.
/// A DJ has no channel to decline a request; request-o-matic's only
/// non-transient rejection on `POST /request` is a `400` for an empty
/// message (`routers/request.py:428`), which ``RequestService`` already
/// refuses client-side as ``RequestServiceError/emptyMessage`` before
/// anything is sent. So the case was unreachable in practice, and where it
/// did render it invented a human judgment that had not happened and asked
/// the listener to reword text nobody had read.
///
/// Collapsing it also closes the ban tell for good. ROM answers a
/// shadow-banned listener with a `403`, and on the unauthenticated path —
/// the whole install base today — that arrives with no JWT, the same shape
/// as an outage. Folding `403` alone into ``boothUnreachable`` left the
/// distinction one status away from returning; with a single answered case
/// there is nothing on screen that varies with what the booth said, so no
/// copy can be probed for a ban. The status code is still reported to
/// PostHog under its own key from the error itself, so nothing measurable
/// is lost.
public enum RequestLineFailure: Equatable, Sendable {
    /// Anonymous auth could not be established, so the request was never
    /// sent. ROM was not contacted. Dominant causes are transient: a 429
    /// from the sign-in limiter, or a Keychain miss on a cold launch.
    case authUnavailable

    /// The request did not land, for every reason other than auth: the POST
    /// never completed, or it completed with a status that isn't success.
    /// Deliberately one case — see the note above.
    case boothUnreachable

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
        case .serverError, .invalidResponse, .encodingFailed, .networkError, .emptyMessage, .userBanned:
            self = .boothUnreachable
        }
    }

    /// The `failure_cause` wire value: the bare case name, so a PostHog
    /// breakdown on it stays one series. A status code that's wanted rides
    /// under its own key instead.
    var analyticsName: String {
        switch self {
        case .authUnavailable: "authUnavailable"
        case .boothUnreachable: "boothUnreachable"
        }
    }
}
