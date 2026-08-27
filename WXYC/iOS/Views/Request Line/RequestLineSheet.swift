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

    /// Raised when the booth has the request. The sheet dismisses itself on
    /// success, so the confirmation HUD has to be presented by whoever
    /// presented the sheet — see `requestSentHUD(outcome:)`.
    let onSent: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.themeAppearance) private var appearance

    @State private var composer: RequestLineComposer
    @FocusState private var composerFocused: Bool

    init(requestLine: RequestLine, source: String, onSent: @escaping () -> Void) {
        self.requestLine = requestLine
        self.source = source
        self.onSent = onSent
        _composer = State(initialValue: RequestLineComposer(source: source))
    }

    private var accent: Color {
        appearance.accentColor.color(brightness: appearance.accentColor.brightness)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            RequestLinePresenceLabel(requestLine: requestLine)

            VStack(alignment: .leading, spacing: 10) {
                Text("Make a request")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                TextField("Song title and artist", text: $composer.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($composerFocused)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(.quaternary, in: .rect(cornerRadius: 12))

                if let failure = composer.failure {
                    RequestLineFailureLabel(failure: failure)
                }

                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        if composer.isSending {
                            ProgressView().tint(.white)
                        }
                        Text("Send to the booth").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(!composer.canSend)
            }
            .animation(.default, value: composer.failure)

            Divider()

            Button {
                placeCall()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Dial a DJ").bold()
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
        // The detent is fixed, so the inline failure row has to be budgeted
        // for — otherwise it pushes the "Dial a DJ" row past the bottom edge.
        // 440 covers the two-line `.authUnavailable` copy at default Dynamic Type.
        .presentationDetents([.height(composer.failure == nil ? 380 : 440)])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("requestLineSheet")
        .onAppear {
            StructuredPostHogAnalytics.shared.capture(RequestLineOpened(source: source))
        }
    }

    /// Posts the typed request to request-o-matic and routes the outcome.
    ///
    /// A success dismisses the sheet and hands the confirmation to the
    /// presenter. A failure keeps the sheet up — the typed text is the whole
    /// reason not to dismiss — and reports itself inline, where a HUD raised
    /// behind the sheet would be occluded by it.
    private func send() async {
        switch await composer.send() {
        case .sent:
            onSent()
            dismiss()
        case .failed, nil:
            break
        }
    }

    /// Opens the request-line `tel:` URL and records the tap. The system call
    /// prompt handles the rest; on a device without telephony this is a no-op.
    private func placeCall() {
        StructuredPostHogAnalytics.shared.capture(RequestLineCallPlaced(source: source))
        openURL(RadioStation.WXYC.requestLine)
    }
}

/// The inline report for a request that didn't reach the booth. Lives in the
/// sheet rather than in the confirmation HUD because the sheet stays up on
/// failure — so the listener can retry without retyping — and would occlude a
/// HUD raised behind it.
///
/// The composer classifies the cause; this view owns the copy, since the copy
/// has to fit the layout budgeted for it (see the sheet's `presentationDetents`).
struct RequestLineFailureLabel: View {
    let failure: RequestLineFailure

    /// The leading clause is semibold, the rest regular, in one `Text` — the
    /// row is already `.font(.footnote).foregroundStyle(.orange)`. Every case
    /// already states "wasn't sent", so VoiceOver reads it once, from here.
    private var message: Text {
        switch failure {
        case .authUnavailable:
            Text("Couldn't connect to WXYC.").fontWeight(.semibold)
                + Text(" Your request wasn't sent — try again in a moment.")
        case .boothUnreachable:
            Text("Couldn't reach the booth.").fontWeight(.semibold)
                + Text(" Your request wasn't sent — try again.")
        case .boothRejected:
            Text("The booth turned that one down.").fontWeight(.semibold)
                + Text(" Try rewording your request.")
        }
    }

    var body: some View {
        Label {
            message
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.footnote)
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
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
            "\(name) is at the controls"
        } else {
            "The booth is open"
        }
    }
}

#Preview("Named DJ") {
    Color.black.sheet(isPresented: .constant(true)) {
        RequestLineSheet(requestLine: RequestLine(onAir: .dj("DJ HOUNDSTOOTH")), source: "banner", onSent: {})
            .environment(Singletonia.shared)
    }
}

#Preview("Send failed") {
    VStack(spacing: 22) {
        RequestLinePresenceLabel(requestLine: RequestLine(onAir: .dj("DJ HOUNDSTOOTH")))
        RequestLineFailureLabel(failure: .authUnavailable)
        RequestLineFailureLabel(failure: .boothUnreachable)
        RequestLineFailureLabel(failure: .boothRejected(statusCode: 500))
    }
    .padding(24)
}
