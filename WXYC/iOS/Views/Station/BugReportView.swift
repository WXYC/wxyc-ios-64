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

    init(
        submitter: any BugReportSubmitter,
        analytics: any AnalyticsService,
        logsProvider: @escaping @Sendable () -> [LogAttachment]
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

                Section("Name (optional)") {
                    TextField("So we know who's reporting", text: $viewModel.name)
                        .textContentType(.name)
                        .autocorrectionDisabled(true)
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
            .alert(
                "Couldn't send report",
                isPresented: Binding(
                    get: { viewModel.presentResult == .failed },
                    set: { if $0 == false { viewModel.presentResult = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.presentResult = nil
                }
            } message: {
                Text("Bug reporting isn't available right now. Please try again later, or send feedback via email instead.")
            }
        }
    }
}
