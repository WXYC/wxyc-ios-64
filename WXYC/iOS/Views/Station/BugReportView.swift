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
                // O5 crash-test build only (WXYC/wxyc-ios-64#1166); never merge
                Section("O5 crash test") {
                    Button("O5: crash now", role: .destructive) {
                        o5TestCrash()
                    }
                    Button("O5: hang 5s") {
                        o5TestHang()
                    }
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

// O5 crash-test build only (WXYC/wxyc-ios-64#1166); never merge
/// Crashes the app with a force-unwrap of nil, so the stack has a frame named `o5TestCrash` in app code.
@inline(never)
func o5TestCrash() {
    let missing: Int? = Int(ProcessInfo.processInfo.environment["O5_NEVER_SET_ENV_VAR"] ?? "")
    print("O5 crash value: \(missing!)")
}

// O5 crash-test build only (WXYC/wxyc-ios-64#1166); never merge
/// Blocks the main thread for 5 seconds so MetricKit records a hang diagnostic.
@MainActor
@inline(never)
func o5TestHang() {
    Thread.sleep(forTimeInterval: 5)
}
