//
//  RequestLineSheet.swift
//  WXYC
//
//  The "Request Line": the listener's two live channels to the booth — a song
//  request (posted to the DJ's Slack via request-o-matic) and the request-line
//  phone call. Presented from the on-air banner's say-hi chip and from the
//  Station tab's booth rows; both entry points pass a `source` for analytics.
//  Only ever shown when the booth is open (a named DJ, or an unreported state
//  that may still be a live human), so it assumes a reachable booth.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Core
import Logger
import MusicShareKit
import Playlist
import SwiftUI
import Wallpaper

struct RequestLineSheet: View {
    /// The booth's current presence, used for the header copy.
    let requestLine: RequestLine

    /// The entry point that opened the sheet: `"banner"` or `"station"`.
    let source: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.themeAppearance) private var appearance

    @State private var requestText = ""
    @State private var isSending = false
    @State private var didSend = false
    @FocusState private var composerFocused: Bool

    private var accent: Color {
        appearance.accentColor.color(brightness: appearance.accentColor.brightness)
    }

    private var trimmedRequest: String {
        requestText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            RequestLinePresenceLabel(requestLine: requestLine)

            VStack(alignment: .leading, spacing: 10) {
                Text("Request a song")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                TextField("Song title and artist", text: $requestText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($composerFocused)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(.quaternary, in: .rect(cornerRadius: 12))

                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        if isSending {
                            ProgressView().tint(.white)
                        }
                        Text(didSend ? "Sent to the booth" : "Send to the booth").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(trimmedRequest.isEmpty || isSending || didSend)
            }

            Divider()

            Button {
                placeCall()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Call the request line").bold()
                        Text("(919) 962-8989")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("requestLineSheet")
        .onAppear {
            StructuredPostHogAnalytics.shared.capture(RequestLineOpened(source: source))
        }
    }

    /// Posts the typed request to request-o-matic, records the send, and
    /// dismisses. Failures are reported but leave the sheet open so the text
    /// isn't lost.
    private func send() async {
        let message = trimmedRequest
        guard !message.isEmpty else { return }

        isSending = true
        defer { isSending = false }

        do {
            try await RequestService.shared.sendRequest(message: message)
            StructuredPostHogAnalytics.shared.capture(RequestLineSongRequested(source: source))
            didSend = true
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        } catch {
            ErrorReporting.shared.report(error, context: "RequestLine", category: .ui)
        }
    }

    /// Opens the request-line `tel:` URL and records the tap. The system call
    /// prompt handles the rest; on a device without telephony this is a no-op.
    private func placeCall() {
        StructuredPostHogAnalytics.shared.capture(RequestLineCallPlaced(source: source))
        openURL(RadioStation.WXYC.requestLine)
    }
}

/// The presence line at the top of the Request Line sheet: a live indicator and
/// the DJ's name when the backend reports one, or a neutral "the booth" when it
/// doesn't. Never rendered under confirmed automation — the sheet isn't shown.
struct RequestLinePresenceLabel: View {
    let requestLine: RequestLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The Request Line")
                .font(.title2.bold())

            HStack(spacing: 7) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        if let name = requestLine.djName {
            "\(name) is on the board"
        } else {
            "The booth is open"
        }
    }
}

#Preview("Named DJ") {
    Color.black.sheet(isPresented: .constant(true)) {
        RequestLineSheet(requestLine: RequestLine(onAir: .dj("DJ HOUNDSTOOTH")), source: "banner")
            .environment(Singletonia.shared)
    }
}
