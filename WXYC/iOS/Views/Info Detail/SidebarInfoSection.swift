//
//  SidebarInfoSection.swift
//  WXYC
//
//  Compact info and action section for the NavigationSplitView sidebar. Provides
//  feedback, request, dial, and merch actions as list rows instead of full-page buttons.
//
//  Created by Jake Bromberg on 04/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Core
import Logger
import MessageUI
import MusicShareKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarInfoSection: View {
    @State private var showingLogPrompt = false
    @State private var showingRequestAlert = false
    @State private var showingMailComposer = false
    @State private var attachLogsToEmail = false
    @State private var requestText = ""

    var body: some View {
        Section {
            Button("Send feedback", systemImage: "envelope.fill") {
                showingLogPrompt = true
            }

            Button("Make a request", systemImage: "message.fill") {
                showingRequestAlert = true
            }

            Button("Dial a DJ", systemImage: "phone.fill") {
                UIApplication.shared.open(RadioStation.WXYC.requestLine)
            }

            Button("Buy merch", systemImage: "tshirt.fill") {
                UIApplication.shared.open(RadioStation.WXYC.merchURL)
            }
        } header: {
            Text(RadioStation.WXYC.name)
        }
        .alert("Is this a bug?", isPresented: $showingLogPrompt) {
            Button("Yes!") {
                attachLogsToEmail = true
                showingMailComposer = true
            }
            Button("S'all good") {
                attachLogsToEmail = false
                showingMailComposer = true
            }
        } message: {
            Text("If you're sending feedback because you spotted a bug, would you mind if we attached some debug logs? This will help us figure out what's going wrong and doesn't include any personal info.")
        }
        .alert("What would you like to request?", isPresented: $showingRequestAlert) {
            TextField("Song title and artist", text: $requestText)
                .autocorrectionDisabled(true)

            Button("Request") {
                Task {
                    await sendRequest(message: requestText)
                    requestText = ""
                }
            }

            Button("Cancel", role: .cancel) {
                requestText = ""
            }
        } message: {
            Text("Please include song title and artist.")
        }
        .sheet(isPresented: $showingMailComposer) {
            MailComposerView(attachLogs: attachLogsToEmail)
        }
    }

    private func sendRequest(message: String) async {
        do {
            try await RequestService.shared.sendRequest(message: message)
        } catch {
            ErrorReporting.shared.report(error, context: "SidebarInfoSection", category: .ui)
        }
    }
}
