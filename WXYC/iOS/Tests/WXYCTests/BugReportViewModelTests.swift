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

    @Test("submit captures bug_report_submitted with the trimmed message and the report ID the logs are tagged with")
    func submitCapturesEventAndTagsLogs() async throws {
        let submitter = RecordingSubmitter()
        let analytics = RecordingAnalytics()
        let viewModel = makeViewModel(submitter: submitter, analytics: analytics)
        viewModel.message = "  Crashes on the playlist tab  "

        await viewModel.submit()

        let event = try #require(analytics.submitted.first)
        #expect(analytics.capturedNames == [BugReportSubmitted.name])
        #expect(event.message == "Crashes on the playlist tab")
        #expect(UUID(uuidString: event.reportId) != nil)
        #expect(submitter.calls.map(\.reportID) == [event.reportId])
        #expect(viewModel.presentResult == .sent)
    }

    @Test("submit forwards the provided log lines")
    func submitForwardsLogs() async {
        let submitter = RecordingSubmitter()
        let viewModel = makeViewModel(submitter: submitter, logs: { ["a", "b"] })
        viewModel.message = "Crash"

        await viewModel.submit()

        #expect(submitter.calls.first?.logLines == ["a", "b"])
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
    logs: @escaping @Sendable () -> [String] = { [] }
) -> BugReportViewModel {
    BugReportViewModel(submitter: submitter, analytics: analytics, logsProvider: logs)
}

private final class RecordingSubmitter: BugReportSubmitter, @unchecked Sendable {
    struct Call: Equatable {
        let reportID: String
        let logLines: [String]
    }

    private(set) var calls: [Call] = []

    func submit(reportID: String, logLines: [String]) {
        calls.append(Call(reportID: reportID, logLines: logLines))
    }
}

private final class RecordingAnalytics: AnalyticsService, @unchecked Sendable {
    private(set) var capturedNames: [String] = []
    private(set) var submitted: [BugReportSubmitted] = []

    func capture<T: AnalyticsEvent>(_ event: T) {
        capturedNames.append(T.name)
        if let event = event as? BugReportSubmitted {
            submitted.append(event)
        }
    }
}
