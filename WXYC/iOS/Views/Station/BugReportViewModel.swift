//
//  BugReportViewModel.swift
//  WXYC
//
//  Holds the editable state for BugReportView and routes submissions through
//  an injected BugReportSubmitter so the flow is testable end-to-end. Reports
//  are anonymous: the event carries the listener's text and a generated ID.
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
    }

    var message: String = ""
    private(set) var isSubmitting: Bool = false
    var presentResult: SubmissionResult?

    private let submitter: any BugReportSubmitter
    private let analytics: any AnalyticsService
    private let logsProvider: @Sendable () -> [String]

    init(
        submitter: any BugReportSubmitter,
        analytics: any AnalyticsService,
        logsProvider: @escaping @Sendable () -> [String]
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

    /// Captures `bug_report_submitted`, then pushes the tagged log lines. Disk reads run
    /// off the MainActor so the UI does not hitch on multi-MB log files. The Send button is
    /// gated on `isSubmitting` to prevent a double-tap from filing two reports.
    func submit() async {
        guard canSend else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let submitter = self.submitter
        let provider = self.logsProvider
        let message = trimmedMessage
        let reportID = UUID().uuidString

        analytics.capture(BugReportSubmitted(reportId: reportID, message: message))

        await Task.detached(priority: .userInitiated) {
            submitter.submit(reportID: reportID, logLines: provider())
        }.value

        presentResult = .sent
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
