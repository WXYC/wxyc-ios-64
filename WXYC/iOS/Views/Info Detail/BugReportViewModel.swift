//
//  BugReportViewModel.swift
//  WXYC
//
//  Holds the editable state for BugReportView and routes submissions through
//  an injected BugReportSubmitter so the flow is testable end-to-end.
//
//  Created by Jake Bromberg on 05/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Foundation

@MainActor
@Observable
final class BugReportViewModel {
    var message: String = ""
    var email: String = ""

    private let submitter: any BugReportSubmitter
    private let analytics: any AnalyticsService
    private let logsProvider: @Sendable () -> LogAttachment?

    init(
        submitter: any BugReportSubmitter,
        analytics: any AnalyticsService,
        logsProvider: @escaping @Sendable () -> LogAttachment?
    ) {
        self.submitter = submitter
        self.analytics = analytics
        self.logsProvider = logsProvider
    }

    var canSend: Bool {
        trimmedMessage.isEmpty == false
    }

    func submit() {
        guard canSend else { return }
        let attachments = logsProvider().map { [$0] } ?? []
        submitter.submit(
            message: trimmedMessage,
            email: trimmedEmail,
            attachments: attachments
        )
        analytics.capture(BugReportSent())
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
