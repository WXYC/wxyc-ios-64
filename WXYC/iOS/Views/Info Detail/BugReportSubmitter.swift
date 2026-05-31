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

protocol BugReportSubmitter: Sendable {
    func submit(message: String, email: String?, attachments: [Data])
}

struct SentryBugReportSubmitter: BugReportSubmitter {
    func submit(message: String, email: String?, attachments: [Data]) {
        let feedback = SentryFeedback(
            message: message,
            name: nil,
            email: email,
            source: .custom,
            associatedEventId: nil,
            attachments: attachments
        )
        SentrySDK.capture(feedback: feedback)
    }
}
