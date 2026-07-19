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
    enum SubmissionResult: Equatable {
        case sent
        case failed
    }

    var message: String = ""
    var name: String = ""
    var email: String = ""
    private(set) var isSubmitting: Bool = false
    var presentResult: SubmissionResult?

    private let submitter: any BugReportSubmitter
    private let analytics: any AnalyticsService
    private let logsProvider: @Sendable () -> [LogAttachment]

    init(
        submitter: any BugReportSubmitter,
        analytics: any AnalyticsService,
        logsProvider: @escaping @Sendable () -> [LogAttachment]
    ) {
        self.submitter = submitter
        self.analytics = analytics
        self.logsProvider = logsProvider
    }

    var canSend: Bool {
        trimmedMessage.isEmpty == false && isSubmitting == false
    }

    func markPresented() {
        analytics.capture(BugReportPresented())
    }

    /// Submits the report. Disk reads and Sentry envelope serialization run off the
    /// MainActor so the UI does not hitch on multi-MB log files. The Send button is
    /// gated on `isSubmitting` to prevent a double-tap from firing two envelopes.
    func submit() async {
        guard canSend else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let submitter = self.submitter
        let provider = self.logsProvider
        let message = trimmedMessage
        let name = trimmedName
        let email = trimmedEmail

        let sent = await Task.detached(priority: .userInitiated) {
            let attachments = provider()
            return submitter.submit(
                message: message,
                name: name,
                email: email,
                attachments: attachments
            )
        }.value

        if sent {
            analytics.capture(BugReportSent())
            presentResult = .sent
        } else {
            presentResult = .failed
        }
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var trimmedEmail: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
