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
    func submitForwardsMessage() async {
        let submitter = RecordingSubmitter()
        let viewModel = makeViewModel(submitter: submitter)
        viewModel.message = "  Crashes on the playlist tab  "

        await viewModel.submit()

        #expect(submitter.calls.count == 1)
        #expect(submitter.calls.first?.message == "Crashes on the playlist tab")
    }

    @Test("submit forwards non-empty name and email")
    func submitForwardsNameAndEmail() async {
        let submitter = RecordingSubmitter()
        let viewModel = makeViewModel(submitter: submitter)
        viewModel.message = "Playback stalls"
        viewModel.name = "Pat Listener"
        viewModel.email = "listener@example.com"

        await viewModel.submit()

        #expect(submitter.calls.first?.name == "Pat Listener")
        #expect(submitter.calls.first?.email == "listener@example.com")
    }

    @Test("submit nils out empty/whitespace name and email")
    func submitNilsEmptyContact() async {
        let submitter = RecordingSubmitter()
        let viewModel = makeViewModel(submitter: submitter)
        viewModel.message = "Playback stalls"
        viewModel.name = "   "
        viewModel.email = ""

        await viewModel.submit()

        #expect(submitter.calls.first?.name == nil)
        #expect(submitter.calls.first?.email == nil)
    }

    @Test("submit forwards log attachment with filename and content type intact")
    func submitForwardsLogs() async {
        let submitter = RecordingSubmitter()
        let attachment = LogAttachment(
            data: Data("debug log contents".utf8),
            filename: "wxyc-2026-05-30.log",
            contentType: "text/plain"
        )
        let viewModel = makeViewModel(submitter: submitter, logs: { [attachment] })
        viewModel.message = "Crash"

        await viewModel.submit()

        #expect(submitter.calls.first?.attachments == [attachment])
    }

    @Test("submit sends empty attachments when logs unavailable")
    func submitNoAttachmentsWhenLogsMissing() async {
        let submitter = RecordingSubmitter()
        let viewModel = makeViewModel(submitter: submitter, logs: { [] })
        viewModel.message = "Crash"

        await viewModel.submit()

        #expect(submitter.calls.first?.attachments.isEmpty == true)
    }

    @Test("submit fires BugReportSent when submitter returns true")
    func submitFiresAnalyticsOnSuccess() async {
        let analytics = RecordingAnalytics()
        let viewModel = makeViewModel(
            submitter: RecordingSubmitter(returns: true),
            analytics: analytics
        )
        viewModel.message = "Crash"

        await viewModel.submit()

        #expect(analytics.capturedNames == [BugReportSent.name])
        #expect(viewModel.presentResult == .sent)
    }

    @Test("submit does not fire BugReportSent when submitter returns false")
    func submitSkipsAnalyticsOnFailure() async {
        let analytics = RecordingAnalytics()
        let viewModel = makeViewModel(
            submitter: RecordingSubmitter(returns: false),
            analytics: analytics
        )
        viewModel.message = "Crash"

        await viewModel.submit()

        #expect(analytics.capturedNames.isEmpty)
        #expect(viewModel.presentResult == .failed)
    }

    @Test("submit is a no-op when canSend is false")
    func submitNoOpWhenCannotSend() async {
        let submitter = RecordingSubmitter()
        let analytics = RecordingAnalytics()
        let viewModel = makeViewModel(submitter: submitter, analytics: analytics)
        viewModel.message = "   "

        await viewModel.submit()

        #expect(submitter.calls.isEmpty)
        #expect(analytics.capturedNames.isEmpty)
        #expect(viewModel.presentResult == nil)
    }

    @Test("isSubmitting is false after submit completes")
    func isSubmittingFalseAfterSubmit() async {
        let viewModel = makeViewModel()
        viewModel.message = "Crash"

        await viewModel.submit()

        #expect(viewModel.isSubmitting == false)
    }

    @Test("markPresented fires BugReportPresented")
    func markPresentedFiresAnalytics() {
        let analytics = RecordingAnalytics()
        let viewModel = makeViewModel(analytics: analytics)

        viewModel.markPresented()

        #expect(analytics.capturedNames == [BugReportPresented.name])
    }
}

// MARK: - Test Helpers

@MainActor
private func makeViewModel(
    submitter: RecordingSubmitter = RecordingSubmitter(),
    analytics: any AnalyticsService = RecordingAnalytics(),
    logs: @escaping @Sendable () -> [LogAttachment] = { [] }
) -> BugReportViewModel {
    BugReportViewModel(submitter: submitter, analytics: analytics, logsProvider: logs)
}

private final class RecordingSubmitter: BugReportSubmitter, @unchecked Sendable {
    struct Call: Equatable {
        let message: String
        let name: String?
        let email: String?
        let attachments: [LogAttachment]
    }

    private(set) var calls: [Call] = []
    private let result: Bool

    init(returns result: Bool = true) {
        self.result = result
    }

    func submit(message: String, name: String?, email: String?, attachments: [LogAttachment]) -> Bool {
        calls.append(Call(message: message, name: name, email: email, attachments: attachments))
        return result
    }
}

private final class RecordingAnalytics: AnalyticsService, @unchecked Sendable {
    private(set) var capturedNames: [String] = []

    func capture<T: AnalyticsEvent>(_ event: T) {
        capturedNames.append(T.name)
    }
}
