//
//  BugReportViewModelTests.swift
//  WXYC
//
//  Tests for the view model backing the in-app bug report sheet.
//
//  Created by Jake Bromberg on 05/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Analytics
@testable import WXYC

@Suite("BugReportViewModel")
@MainActor
struct BugReportViewModelTests {

    @Test("canSend is false when message is empty")
    func canSendFalseWhenEmpty() {
        let viewModel = makeViewModel()

        #expect(viewModel.canSend == false)
    }

    @Test("canSend is false when message is only whitespace")
    func canSendFalseWhenWhitespace() {
        let viewModel = makeViewModel()
        viewModel.message = "   \n\t  "

        #expect(viewModel.canSend == false)
    }

    @Test("canSend is true when message has content")
    func canSendTrueWhenContent() {
        let viewModel = makeViewModel()
        viewModel.message = "Playback stalls on launch"

        #expect(viewModel.canSend == true)
    }

    @Test("submit forwards trimmed message to submitter")
    func submitForwardsMessage() {
        let submitter = RecordingSubmitter()
        let viewModel = makeViewModel(submitter: submitter)
        viewModel.message = "  Crashes on the playlist tab  "

        viewModel.submit()

        #expect(submitter.calls.count == 1)
        #expect(submitter.calls.first?.message == "Crashes on the playlist tab")
    }

    @Test("submit forwards non-empty email")
    func submitForwardsEmail() {
        let submitter = RecordingSubmitter()
        let viewModel = makeViewModel(submitter: submitter)
        viewModel.message = "Playback stalls"
        viewModel.email = "listener@example.com"

        viewModel.submit()

        #expect(submitter.calls.first?.email == "listener@example.com")
    }

    @Test("submit nils out empty email")
    func submitNilsEmptyEmail() {
        let submitter = RecordingSubmitter()
        let viewModel = makeViewModel(submitter: submitter)
        viewModel.message = "Playback stalls"
        viewModel.email = ""

        viewModel.submit()

        #expect(submitter.calls.first?.email == nil)
    }

    @Test("submit nils out whitespace-only email")
    func submitNilsWhitespaceEmail() {
        let submitter = RecordingSubmitter()
        let viewModel = makeViewModel(submitter: submitter)
        viewModel.message = "Playback stalls"
        viewModel.email = "   "

        viewModel.submit()

        #expect(submitter.calls.first?.email == nil)
    }

    @Test("submit forwards log attachment with filename and content type intact")
    func submitForwardsLogs() {
        let submitter = RecordingSubmitter()
        let attachment = LogAttachment(
            data: Data("debug log contents".utf8),
            filename: "wxyc-2026-05-30.log",
            contentType: "text/plain"
        )
        let viewModel = makeViewModel(submitter: submitter, logs: { attachment })
        viewModel.message = "Crash"

        viewModel.submit()

        #expect(submitter.calls.first?.attachments == [attachment])
    }

    @Test("submit sends no attachments when logs unavailable")
    func submitNoAttachmentsWhenLogsMissing() {
        let submitter = RecordingSubmitter()
        let viewModel = makeViewModel(submitter: submitter, logs: { nil })
        viewModel.message = "Crash"

        viewModel.submit()

        #expect(submitter.calls.first?.attachments.isEmpty == true)
    }

    @Test("submit fires BugReportSent analytics event")
    func submitFiresAnalyticsEvent() {
        let analytics = RecordingAnalytics()
        let viewModel = makeViewModel(analytics: analytics)
        viewModel.message = "Crash"

        viewModel.submit()

        #expect(analytics.capturedNames == [BugReportSent.name])
    }

    @Test("submit is a no-op when canSend is false")
    func submitNoOpWhenCannotSend() {
        let submitter = RecordingSubmitter()
        let analytics = RecordingAnalytics()
        let viewModel = makeViewModel(submitter: submitter, analytics: analytics)
        viewModel.message = "   "

        viewModel.submit()

        #expect(submitter.calls.isEmpty)
        #expect(analytics.capturedNames.isEmpty)
    }
}

// MARK: - Test Helpers

@MainActor
private func makeViewModel(
    submitter: RecordingSubmitter = RecordingSubmitter(),
    analytics: any AnalyticsService = RecordingAnalytics(),
    logs: @escaping @Sendable () -> LogAttachment? = { nil }
) -> BugReportViewModel {
    BugReportViewModel(submitter: submitter, analytics: analytics, logsProvider: logs)
}

private final class RecordingSubmitter: BugReportSubmitter, @unchecked Sendable {
    struct Call: Equatable {
        let message: String
        let email: String?
        let attachments: [LogAttachment]
    }

    private(set) var calls: [Call] = []

    func submit(message: String, email: String?, attachments: [LogAttachment]) {
        calls.append(Call(message: message, email: email, attachments: attachments))
    }
}

private final class RecordingAnalytics: AnalyticsService, @unchecked Sendable {
    private(set) var capturedNames: [String] = []

    func capture<T: AnalyticsEvent>(_ event: T) {
        capturedNames.append(T.name)
    }
}
