//
//  BugReportView.swift
//  WXYC
//
//  Sheet for collecting a free-text bug report and submitting it to PostHog
//  (an event plus the recent log lines). Replaces the email-based bug branch of
//  the feedback flow in InfoDetailView.
//
//  Created by Jake Bromberg on 05/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import SwiftUI
import WXUI

struct BugReportView: View {
    @State private var viewModel: BugReportViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        submitter: any BugReportSubmitter,
        analytics: any AnalyticsService,
        logsProvider: @escaping @Sendable () -> [String]
    ) {
        self._viewModel = State(
            wrappedValue: BugReportViewModel(
                submitter: submitter,
                analytics: analytics,
                logsProvider: logsProvider
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What went wrong?") {
                    TextEditor(text: $viewModel.message)
                        .frame(minHeight: 160)
                }
            }
            .sheetChrome(title: "Report a bug", showsDoneButton: false)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .disabled(viewModel.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Button("Send") {
                            Task { await viewModel.submit() }
                        }
                        .disabled(viewModel.canSend == false)
                    }
                }
            }
            .onAppear {
                viewModel.markPresented()
            }
            .alert(
                "Report sent",
                isPresented: Binding(
                    get: { viewModel.presentResult == .sent },
                    set: { if $0 == false { viewModel.presentResult = nil; dismiss() } }
                )
            ) {
                Button("OK") {
                    viewModel.presentResult = nil
                    dismiss()
                }
            } message: {
                Text("Thanks — we'll take a look.")
            }
        }
    }
}
