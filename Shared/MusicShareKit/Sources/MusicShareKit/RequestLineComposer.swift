//
//  RequestLineComposer.swift
//  MusicShareKit
//
//  Send logic for the Request Line's song-request composer, lifted out of the
//  sheet so the success and failure branches are testable.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Foundation

/// Owns the text a listener types into the Request Line and the one-shot send
/// that follows.
///
/// The two outcomes are presented differently, and the composer is deliberately
/// agnostic about which: a success dismisses the sheet, so its confirmation has
/// to be raised by whoever presented it (see `requestSentHUD(outcome:)`), while
/// a failure keeps the sheet up and reports itself inline through ``failure``.
/// ``send()`` returns the outcome so the view can route it.
@MainActor
@Observable
public final class RequestLineComposer {
    /// What the listener has typed. Editing clears a stale ``failure``.
    public var text: String = "" {
        didSet { failure = nil }
    }

    /// True while a send is in flight.
    public private(set) var isSending = false

    /// Why a send didn't land, or `nil` when there's nothing to report.
    /// Displayed inline, next to the composer.
    public private(set) var failure: RequestLineFailure?

    private let requestSender: any RequestSending
    private let analytics: any AnalyticsService
    private let source: String

    /// - Parameters:
    ///   - source: The entry point that opened the Request Line, for analytics:
    ///     `"banner"` or `"station"`.
    ///   - requestSender: The seam that posts to request-o-matic.
    ///   - analytics: Injected rather than read off `MusicShareKit.configuration`,
    ///     which `fatalError`s until `configure()` has run — a composer built in
    ///     a SwiftUI preview would trip it. Tests inject a mock.
    public init(
        source: String,
        requestSender: any RequestSending = RequestService.shared,
        analytics: any AnalyticsService = StructuredPostHogAnalytics.shared
    ) {
        self.source = source
        self.requestSender = requestSender
        self.analytics = analytics
    }

    /// The message as it will be sent.
    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether there's something to send and nothing already in flight.
    public var canSend: Bool {
        !trimmedText.isEmpty && !isSending
    }

    /// Posts the typed request to the booth.
    ///
    /// - Returns: The outcome to present, or `nil` when there was nothing to
    ///   send — an empty composer, or a send already in flight.
    @discardableResult
    public func send() async -> RequestSentOutcome? {
        guard canSend else { return nil }

        let message = trimmedText
        isSending = true
        defer { isSending = false }

        do {
            // A shadow-banned listener takes this branch too: `RequestService`
            // returns without throwing on a 403 so the ban stays invisible.
            // Suppressing the confirmation here would be the tell.
            try await requestSender.sendRequest(message: message)
            analytics.capture(RequestLineSongRequested(source: source))
            failure = nil
            return .sent
        } catch {
            let cause = RequestLineFailure(error)
            var additionalData = ["failure_cause": cause.analyticsName]
            // Taken from the error, not from `cause`. Nothing on screen
            // varies with the status — that is what keeps a ban unprobeable
            // — but the status is still worth having in PostHog, so the two
            // sources are deliberately separate.
            if case .serverError(let statusCode) = error as? RequestServiceError {
                additionalData["status_code"] = String(statusCode)
            }
            // Reported through the injected `analytics` — not the
            // process-global `ErrorReporting.shared` — so the split this
            // exists to measure is observable by a test against
            // `MockStructuredAnalytics` rather than unpinned.
            analytics.captureError(error, context: "RequestLine", category: "UI", additionalData: additionalData)
            failure = cause
            return .failed
        }
    }
}
