//
//  BugReportView.swift
//  WXYC
//
//  Sheet for collecting a free-text bug report and submitting it to Sentry's
//  user feedback channel. Replaces the email-based bug branch of the feedback
//  flow in InfoDetailView.
//
//  Created by Jake Bromberg on 05/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import SwiftUI

struct BugReportView: View {
    @State private var viewModel: BugReportViewModel
    @Environment(\.dismiss) private var dismiss
    private let analytics: any AnalyticsService

    init(
        submitter: any BugReportSubmitter,
        analytics: any AnalyticsService,
        logsProvider: @escaping @Sendable () -> LogAttachment?
    ) {
        self._viewModel = State(
            wrappedValue: BugReportViewModel(
                submitter: submitter,
                analytics: analytics,
                logsProvider: logsProvider
            )
        )
        self.analytics = analytics
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What went wrong?") {
                    TextEditor(text: $viewModel.message)
                        .frame(minHeight: 160)
                }

                Section("Email (optional)") {
                    TextField("So we can follow up", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Report a bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        viewModel.submit()
                        dismiss()
                    }
                    .disabled(viewModel.canSend == false)
                }
            }
            .onAppear {
                analytics.capture(BugReportPresented())
            }
        }
    }
}
