//
//  BugReportSubmitter.swift
//  WXYC
//
//  Abstraction over Sentry's user feedback API so the bug report flow can be
//  exercised in tests without invoking the live SDK.
//
//  Created by Jake Bromberg on 05/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Sentry

nonisolated struct LogAttachment: Equatable, Sendable {
    let data: Data
    let filename: String
    let contentType: String
}

nonisolated protocol BugReportSubmitter: Sendable {
    /// Submits a bug report to the underlying feedback backend.
    ///
    /// - Returns: `true` if the backend was enabled and accepted the envelope for transport,
    ///   `false` if submission was skipped (e.g., the Sentry SDK is disabled). Callers should
    ///   only fire success analytics when this returns `true`.
    func submit(message: String, name: String?, email: String?, attachments: [LogAttachment]) -> Bool
}

nonisolated struct SentryBugReportSubmitter: BugReportSubmitter {
    // SentryFeedback's own `attachments` parameter rewrites every Data blob to
    // `screenshot.png` / `application/png` (see sentry-cocoa SentryFeedback.swift),
    // so log files sent through it arrive at Sentry mislabeled and the web UI
    // refuses to render them. We route attachments through the global scope
    // (SentryClient.captureFeedback:withScope: concatenates scope.attachments with
    // the feedback envelope, preserving filename + content type) and unconditionally
    // clear the scope's attachments afterwards so a previous submission whose clear
    // was preempted does not leak into the next event.
    //
    // Trade-off: `clearAttachments` wipes the scope's full attachment list, not just
    // the entries we added. This is safe today because nothing else in the WXYC app
    // uses scope attachments. Revisit if another integration starts attaching to
    // the global scope.
    func submit(message: String, name: String?, email: String?, attachments: [LogAttachment]) -> Bool {
        guard SentrySDK.isEnabled else { return false }

        let sentryAttachments = attachments.map { attachment in
            Attachment(
                data: attachment.data,
                filename: attachment.filename,
                contentType: attachment.contentType
            )
        }

        SentrySDK.configureScope { scope in
            for attachment in sentryAttachments {
                scope.addAttachment(attachment)
            }
        }

        let feedback = SentryFeedback(
            message: message,
            name: name,
            email: email,
            source: .custom,
            associatedEventId: nil,
            attachments: nil
        )
        SentrySDK.capture(feedback: feedback)

        SentrySDK.configureScope { scope in
            scope.clearAttachments()
        }

        return true
    }
}
