//
//  InfoDetailView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import MessageUI
import UniformTypeIdentifiers
import Core
import Logger
import PostHog
import Analytics
import MusicShareKit
import WXUI
import Wallpaper

struct InfoDetailView: View {
    @State private var showingLogPrompt = false
    @State private var showingRequestAlert = false
    @State private var showingMailComposer = false
    @State private var attachLogsToEmail = false
    @State private var requestText = ""
    @Environment(Singletonia.self) private var appState

    var body: some View {
        VStack(alignment: .center) {
            Spacer()
            
            FittingText("You're tuned in.")
//                .font(.largeTitle.pointSize(72))
                .fontWeight(.black)
                .foregroundStyle(.white)
                .padding(.bottom)
            
            Text(RadioStation.WXYC.description)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.bottom)
            
            VStack(spacing: 16) {
                ActionButton(
                    title: "Send us feedback on the app",
                    icon: "envelope.fill",
                    color: .red
                ) {
                    showingLogPrompt = true
                }

                ActionButton(
                    title: "Make a request",
                    icon: "message.fill",
                    color: .blue
                ) {
                    showingRequestAlert = true
                }

                ActionButton(
                    title: "Dial a DJ",
                    icon: "phone.fill",
                    color: .green
                ) {
                    UIApplication.shared.open(RadioStation.WXYC.requestLine)
                }
                
                ActionButton(
                    title: "Buy cool merch",
                    icon: "tshirt",
                    color: .purple
                ) {
                    UIApplication.shared.open(RadioStation.WXYC.merchURL)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal)
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
        .wallpaperPickerGesture(
            pickerState: appState.wallpaperPickerState,
            configuration: appState.wallpaperConfiguration
        )
    }

    private func sendRequest(message: String) async {
        do {
            try await RequestService.shared.sendRequest(message: message)
        } catch {
            Log(.error, "Error sending request: \(error)")
            PostHogSDK.shared.capture(error: error, context: "Info ViewController")
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .fontWeight(.bold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .glassEffectClearIfAvailable()
            .background(
                Capsule()
                    .fill(color)
            )
        }
    }
}

// MARK: - Mail Composer

struct MailComposerView: UIViewControllerRepresentable {
    let attachLogs: Bool
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        PostHogSDK.shared.capture("feedback email presented")

        let mailComposerVC = MFMailComposeViewController()
        mailComposerVC.mailComposeDelegate = context.coordinator
        mailComposerVC.setToRecipients(["feedback@wxyc.org"])
        mailComposerVC.setSubject("Feedback on the \(RadioStation.WXYC.name) app")

        if attachLogs,
           let (fileName, data) = Logger.fetchLogs() {
            let mimeType = UTType.plainText.preferredMIMEType ?? "plain/text"
            mailComposerVC.addAttachmentData(data, mimeType: mimeType, fileName: fileName)
        }

        return mailComposerVC
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            if let error {
                PostHogSDK.shared.capture(error: error, context: "feedbackEmail")
                Log(.error, "Failed to send feedback email: \(error)")
            } else {
                PostHogSDK.shared.capture("feedback email sent")
            }

            dismiss()
        }
    }
}

struct FittingText: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 100))   // large “base” size
            .lineLimit(1)               // single line only
            .minimumScaleFactor(0.01)   // allow shrinking down to 1% if needed
            .allowsTightening(true)     // optional: tighter kerning
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    InfoDetailView()
        .environment(Singletonia.shared)
        .background(WXYCBackground())
}
