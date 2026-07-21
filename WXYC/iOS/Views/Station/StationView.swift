//
//  StationView.swift
//  WXYC
//
//  The Station tab: station identity plus the listener's channels to the studio,
//  regrouped from the former "Info" grab bag (see
//  docs/ideas/info-tab-junk-drawer.html). Three groups in order of intent — talk
//  to the booth, support the station, this app. The booth rows are on-air-aware:
//  under confirmed automation they disable, because an empty booth reads no
//  requests and answers no phone; under an unreported on-air state they stay
//  enabled, since a human may be on the board. The always-available booth rows
//  are also the fallback entry point to the Request Line when the Now Playing
//  banner (and its say-hi chip) is hidden.
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import Core
import Logger
import MessageUI
import MusicShareKit
import Playlist
import SwiftUI
import UniformTypeIdentifiers
import Wallpaper
import WXUI

struct StationView: View {
    @State private var onAir: OnAir = .unknown
    @State private var showingRequestLine = false
    @State private var showingLogPrompt = false
    @State private var showingMailComposer = false
    @State private var showingBugReport = false

    @Environment(\.playlistService) private var playlistService
    @Environment(\.openURL) private var openURL

    /// Booth presence, derived from the live on-air signal. Drives whether the
    /// "Talk to the booth" rows are enabled.
    private var requestLine: RequestLine {
        RequestLine(onAir: onAir)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StationHero()

                StationSection(
                    caption: "Talk to the booth",
                    footnote: requestLine.boothIsOpen ? nil : "Opens when a DJ signs on."
                ) {
                    StationRow(
                        title: "Make a request",
                        subtitle: "Lands in the DJ booth",
                        systemImage: "message.fill",
                        iconColor: .blue,
                        isEnabled: requestLine.boothIsOpen
                    ) {
                        showingRequestLine = true
                    }

                    StationRow(
                        title: "Call the request line",
                        subtitle: callSubtitle,
                        systemImage: "phone.fill",
                        iconColor: .green,
                        isEnabled: requestLine.boothIsOpen
                    ) {
                        placeCall()
                    }
                }

                StationSection(caption: "Support the station") {
                    StationRow(
                        title: "Buy cool merch",
                        subtitle: "merch.wxyc.org",
                        systemImage: "tshirt.fill",
                        iconColor: .purple
                    ) {
                        openURL(RadioStation.WXYC.merchURL)
                    }
                }

                StationSection(caption: "This app") {
                    StationRow(
                        title: "Send feedback",
                        subtitle: "Report a bug or say hi",
                        systemImage: "envelope.fill",
                        iconColor: .red
                    ) {
                        showingLogPrompt = true
                    }
                }

                Text(RadioStation.WXYC.description)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .accessibilityIdentifier("stationView")
        .task {
            guard let playlistService else { return }
            for await playlist in playlistService.updates() {
                onAir = playlist.onAir
            }
        }
        .sheet(isPresented: $showingRequestLine) {
            RequestLineSheet(requestLine: requestLine, source: "station")
        }
        .alert("Is this a bug?", isPresented: $showingLogPrompt) {
            Button("Yes!") {
                showingBugReport = true
            }
            Button("S'all good") {
                showingMailComposer = true
            }
        } message: {
            Text("If you're reporting a bug, we'll attach some debug logs to help us figure out what's going wrong. They don't include any personal info.")
        }
        .sheet(isPresented: $showingMailComposer) {
            MailComposerView()
        }
        .sheet(isPresented: $showingBugReport) {
            BugReportView(
                submitter: SentryBugReportSubmitter(),
                analytics: StructuredPostHogAnalytics.shared,
                logsProvider: collectBugReportLogs
            )
        }
    }

    /// The call row's subtitle: the number when the booth is open, or a plain
    /// reason when it isn't (mirrors the disabled state so the row reads
    /// honestly even to someone who can't perceive the dimming).
    private var callSubtitle: String {
        requestLine.boothIsOpen ? "(919) 962-8989" : "Nobody's at the phone right now"
    }

    /// Dials the request line and records the tap with a `station` source so the
    /// two entry points (banner vs. Station) can be told apart in analytics.
    private func placeCall() {
        StructuredPostHogAnalytics.shared.capture(RequestLineCallPlaced(source: "station"))
        openURL(RadioStation.WXYC.requestLine)
    }
}

// MARK: - Hero

/// The station-identity header: the WXYC logo over the "You're tuned in."
/// wordmark, both over the wallpaper. The full mission statement moves to a
/// quiet footnote at the bottom of the page, so identity leads without a wall
/// of text.
struct StationHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image("logo white")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .scaleEffect(0.85)
                .padding(.top, 10)
                .accessibilityHidden(true)

            FittingText("You're tuned in.")
                .fontWeight(.black)
                .foregroundStyle(.white)
                .padding(.vertical, 8)
        }
    }
}

// MARK: - Section

/// A captioned group of ``StationRow``s rendered as one glass card, with an
/// optional footnote beneath (used to explain why the booth rows are disabled).
struct StationSection<Content: View>: View {
    let caption: String
    var footnote: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(caption)
                .font(.caption.smallCaps())
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 10)

            VStack(spacing: 0) {
                content()
            }
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.08))
            )

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.top, 1)
            }
        }
    }
}

// MARK: - Row

/// A single tappable Station row: a colored icon tile, a title with an optional
/// subtitle, and a trailing chevron. Disables (and dims) when `isEnabled` is
/// false. The button's accessibility label is exactly the title so UI tests and
/// VoiceOver read the action, not the decorative subtitle.
struct StationRow: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    let iconColor: Color
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(iconColor, in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
    }
}

// MARK: - Mail Composer

struct MailComposerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        StructuredPostHogAnalytics.shared.capture(FeedbackEmailPresented())

        let mailComposerVC = MFMailComposeViewController()
        mailComposerVC.mailComposeDelegate = context.coordinator
        mailComposerVC.setToRecipients(["feedback@wxyc.org"])
        mailComposerVC.setSubject("Feedback on the \(RadioStation.WXYC.name) app")

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
                ErrorReporting.shared.report(error, context: "feedbackEmail", category: .ui)
            } else {
                StructuredPostHogAnalytics.shared.capture(FeedbackEmailSent())
            }

            dismiss()
        }
    }
}

// MARK: - Fitting Text

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

// MARK: - Bug-report logs

/// Collects log files for a bug-report submission. Each file becomes its own
/// `LogAttachment`; oversized files are truncated to their last 20 MB so they
/// fit under Sentry's default per-attachment cap (anything larger is silently
/// dropped server-side). `nonisolated` + top-level so it can be passed to
/// `BugReportView`'s `@Sendable` `logsProvider` from the MainActor view body.
nonisolated func collectBugReportLogs() -> [LogAttachment] {
    let maxBytes = 20 * 1024 * 1024
    let contentType = UTType.plainText.preferredMIMEType ?? "text/plain"
    return Logger.fetchAllLogs()
        .sorted { $0.logName > $1.logName }
        .map { entry in
            let trimmed = entry.data.count > maxBytes
                ? entry.data.suffix(maxBytes)
                : entry.data
            return LogAttachment(
                data: Data(trimmed),
                filename: entry.logName,
                contentType: contentType
            )
        }
}

#Preview("Station") {
    StationView()
        .environment(Singletonia.shared)
        .environment(\.playlistService, PlaylistService())
        .background(WXYCBackground())
}
