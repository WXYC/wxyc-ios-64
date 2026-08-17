//
//  HTTPURLResponse+Validation.swift
//  Core
//
//  Extension on HTTPURLResponse providing HTTP status code validation for
//  success (2xx) responses, replacing duplicated inline checks across packages.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

extension HTTPURLResponse {
    /// Validates that the HTTP status code is in the 2xx success range.
    ///
    /// - Throws: ``HTTPStatusError`` carrying `statusCode` (and, when the
    ///   response advertised one, `retryAfter`) if the status code is
    ///   outside the 200...299 range.
    public func validateSuccessStatus() throws {
        guard (200...299).contains(statusCode) else {
            throw HTTPStatusError(statusCode: statusCode, retryAfter: retryAfterDelay)
        }
    }

    /// The server-advertised retry delay from a `Retry-After` header,
    /// parsed as delta-seconds — RFC 9110 §10.2.3's `delay-seconds` form, a
    /// non-negative decimal integer of seconds to wait.
    ///
    /// The header's other permitted form, an HTTP-date, is deliberately
    /// **not** parsed. Backend-Service's proxy rate limiter
    /// (`express-rate-limit` configured with `standardHeaders: true`, in
    /// `apps/backend/middleware/rateLimiting.ts`) unconditionally emits
    /// delta-seconds — `Retry-After: <windowSeconds>` — and never an
    /// HTTP-date, so a date parser here would guard against a format this
    /// app has never received on the wire. A response carrying an
    /// HTTP-date `Retry-After` is treated the same as a response with no
    /// header at all: `nil`.
    ///
    /// This only *parses*. Range-checking the result is ``HTTPStatusError``'s
    /// job — see its initializer — so the "can't trap a consumer" guarantee
    /// holds for every producer of the type rather than only for this one.
    private var retryAfterDelay: TimeInterval? {
        guard let headerValue = value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(headerValue.trimmingCharacters(in: .whitespaces))
    }
}

/// An HTTP response outside the 2xx success range.
///
/// Replaces the bare `URLError(.badServerResponse)` previously thrown by
/// ``HTTPURLResponse/validateSuccessStatus()`` for every non-2xx status —
/// that case carries no payload, so a 401 and a 503 were indistinguishable
/// in logs and Sentry breadcrumbs (both printed as `-1011 "(null)"`).
/// Carrying `statusCode` lets callers branch on the real status (e.g. a 401
/// triggering a reauthenticate-and-retry) and lets diagnostics show what
/// actually happened.
public struct HTTPStatusError: Error, Equatable {
    /// The non-2xx HTTP status code the server responded with.
    public let statusCode: Int

    /// The server's advertised backoff for this response, parsed from a
    /// `Retry-After` header when the response carried one in delta-seconds
    /// form (see ``HTTPURLResponse/validateSuccessStatus()``). `nil` when
    /// the response had no such header, or the header wasn't in a form this
    /// app parses. A retrying consumer may prefer this over its own
    /// hard-coded backoff schedule; nothing requires it to.
    ///
    /// Guaranteed to lie in `0...maximumRetryAfterSeconds` when non-`nil`, so
    /// a consumer can build a `Duration` from it without checking — see
    /// ``init(statusCode:retryAfter:)``.
    ///
    /// Note that this participates in the synthesized `Equatable` conformance,
    /// so `error == HTTPStatusError(statusCode: 429)` is also an assertion that
    /// the response carried *no* `Retry-After`. Where that isn't the intent —
    /// most `#expect(throws:)` assertions — match on the type and check
    /// `statusCode` explicitly instead.
    public let retryAfter: TimeInterval?

    /// - Parameter retryAfter: A server-advertised backoff in seconds. Values
    ///   outside `0...maximumRetryAfterSeconds` — including infinities and NaN
    ///   — are discarded as `nil` rather than stored.
    ///
    ///   The check lives here, at the type boundary, rather than in the header
    ///   parser, because this initializer is public: test doubles, stub
    ///   fetchers, and any future non-`validateSuccessStatus()` producer reach
    ///   it too. `Duration.seconds(_:)` *traps* on a value it cannot represent,
    ///   and building a `Duration` from this field is precisely what a retrying
    ///   consumer does — so an unchecked value here is a process abort in the
    ///   consumer, whether it arrived from a hostile intermediary's header or
    ///   from a careless stub.
    public init(statusCode: Int, retryAfter: TimeInterval? = nil) {
        self.statusCode = statusCode
        self.retryAfter = retryAfter.flatMap { seconds in
            (0...HTTPStatusError.maximumRetryAfterSeconds).contains(seconds) ? seconds : nil
        }
    }

    /// The largest `Retry-After` this type will carry, in seconds: one day.
    ///
    /// Chosen to sit far above anything a real server advertises —
    /// Backend-Service's proxy limiter sends `60` — while staying far below the
    /// magnitudes that make `Duration.seconds(_:)` trap. A client asked to wait
    /// longer than a day has been told something it will never act on anyway.
    public static let maximumRetryAfterSeconds: TimeInterval = 86_400
}

/// Diagnostics-sink bridging: without these conformances, the NSError bridge
/// collapses every status to `code 1` with a generic message — which is what
/// PostHog's `ErrorEvent` (`nsError.code`/`nsError.domain`) and Sentry event
/// titles record, re-creating the very 401-vs-503 blindness this type exists
/// to fix. `errorCode` carries the HTTP status so those sinks can group and
/// filter on it.
extension HTTPStatusError: CustomNSError, LocalizedError {
    /// Matches the default Swift-runtime bridge domain, so pre-conformance
    /// events keep grouping with post-conformance ones.
    public static let errorDomain = "Core.HTTPStatusError"

    public var errorCode: Int { statusCode }

    public var errorDescription: String? {
        "HTTP \(statusCode)"
    }
}
