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
    func submit(message: String, email: String?, attachments: [LogAttachment])
}

nonisolated struct SentryBugReportSubmitter: BugReportSubmitter {
    // SentryFeedback's own `attachments` parameter rewrites every Data blob to
    // `screenshot.png` / `application/png` (see sentry-cocoa SentryFeedback.swift),
    // so log files sent through it arrive at Sentry mislabeled and the web UI
    // refuses to render them. The scope-attachment path concatenates with the
    // feedback envelope (SentryClient.captureFeedback:withScope:) and preserves
    // the filename + content type, so we route attachments through the scope
    // and clear it again to avoid leaking into subsequent events.
    func submit(message: String, email: String?, attachments: [LogAttachment]) {
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
            name: nil,
            email: email,
            source: .custom,
            associatedEventId: nil,
            attachments: nil
        )
        SentrySDK.capture(feedback: feedback)

        if sentryAttachments.isEmpty == false {
            SentrySDK.configureScope { scope in
                scope.clearAttachments()
            }
        }
    }
}
