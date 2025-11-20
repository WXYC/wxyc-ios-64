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
import Secrets

struct InfoDetailView: View {
    @State private var showingLogPrompt = false
    @State private var showingRequestAlert = false
    @State private var showingMailComposer = false
    @State private var attachLogsToEmail = false
    @State private var requestText = ""

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
        guard !message.isEmpty else { return }

        do {
            guard let webhookURL = try await fetchWebhookURL() else {
                Log(.error, "Failed to fetch webhook URL from Railway endpoint")
                return
            }

            var request = URLRequest(url: webhookURL)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-type")

            let json: [String: Any] = ["text": message]
            guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else { return }
            request.httpBody = jsonData

            PostHogSDK.shared.capture(
                "Request sent",
                context: "Info ViewController",
                additionalData: [
                    "message": message
                ]
            )

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let response = response as? HTTPURLResponse else {
                Log(.error, "No response object from Slack")
                return
            }

            if response.statusCode == 200 {
                Log(.info, "Response status code: \(response.statusCode)")
            } else {
                Log(.error, "Response status code: \(response.statusCode)")
                Log(.error, "Data: \(String(data: data, encoding: .utf8) ?? "nil")")
            }

        } catch {
            Log(.error, "Error sending message to Slack: \(error)")
            PostHogSDK.shared.capture(error: error, context: "Info ViewController")
        }
    }

    private func fetchWebhookURL() async throws -> URL? {
        guard let url = URL(string: Secrets.slackWxycRequestsWebhookRetrievalUrl) else {
            Log(.error, "Invalid Railway endpoint URL")
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let response = response as? HTTPURLResponse else {
                Log(.error, "No response object from Railway endpoint")
                return nil
            }

            guard response.statusCode == 200 else {
                Log(.error, "Railway endpoint returned status code: \(response.statusCode)")
                return nil
            }

            guard let webhookURLSuffixString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                Log(.error, "Failed to unwrap webhook URL from Railway endpoint response")
                return nil
            }

            // The endpoint returns the webhook URL as plain text
            guard let webhookURLSuffix = URL(string: Secrets.slackWxycRequestsWebhook + webhookURLSuffixString) else {
                Log(.error, "Failed to parse webhook URL from Railway endpoint response")
                return nil
            }

            Log(.info, "Successfully fetched webhook URL from Railway endpoint: \(webhookURLSuffix)")
            return webhookURLSuffix
        } catch {
            Log(.error, "Error fetching webhook URL from Railway endpoint: \(error)")
            throw error
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
            .background(
                RoundedRectangle(cornerRadius: 8)
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

struct JustifiedText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor = .white
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textAlignment = .justified
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
        uiView.font = font
        uiView.textColor = textColor
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
        .background(
            Image("background")
                .resizable()
                .ignoresSafeArea()
        )
}
