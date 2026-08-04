//
//  RequestSentHUD.swift
//  MusicShareKit
//
//  Transient HUD shown after a song request is submitted, in the style of the
//  system volume/AirDrop HUDs.
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

struct RequestSentHUD: View {
    let outcome: RequestSentOutcome

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: outcome.systemImage)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)

            Text(outcome.title)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        // Square at default type sizes, like the system HUDs, but allowed to
        // grow rather than clip the label at accessibility sizes.
        .frame(minWidth: 140, minHeight: 140)
        .fixedSize()
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .shadow(radius: 2.5, y: 1.5)
        // The HUD steals no focus, so VoiceOver would otherwise never mention
        // it. The announcement carries the full sentence; the label covers a
        // listener who navigates to it before it dismisses.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(outcome.accessibilityAnnouncement)
        .accessibilityAddTraits(.isStaticText)
        .onAppear {
            AccessibilityNotification.Announcement(outcome.accessibilityAnnouncement).post()
        }
    }
}

// MARK: - ViewModifier

struct RequestSentHUDModifier: ViewModifier {
    @Binding var outcome: RequestSentOutcome?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let outcome {
                    RequestSentHUD(outcome: outcome)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: outcome)
            // Keyed on the outcome so each one gets its own delay, and so a
            // pending dismissal is cancelled when the view goes away. The
            // `isCancelled` check matters: a cancelled sleep throws, `try?`
            // swallows it, and without the guard the HUD would clear itself
            // the instant it was interrupted.
            .task(id: outcome) {
                guard let outcome else { return }
                try? await Task.sleep(for: outcome.autoDismissDelay)
                guard !Task.isCancelled else { return }
                self.outcome = nil
            }
    }
}

public extension View {
    /// Presents a transient confirmation over this view when `outcome` is
    /// non-`nil`, clearing it once the HUD has had its time on screen.
    ///
    /// Attach this to whatever remains on screen after the submission — the
    /// presenter of a sheet that dismisses on success, not the sheet itself,
    /// which would take its own overlay down with it.
    func requestSentHUD(outcome: Binding<RequestSentOutcome?>) -> some View {
        modifier(RequestSentHUDModifier(outcome: outcome))
    }
}

private struct RequestSentHUDPreview: View {
    @State private var outcome: RequestSentOutcome?

    var body: some View {
        VStack(spacing: 20) {
            Button("Send Request") { outcome = .sent }
            Button("Fail to Send") { outcome = .failed }
        }
        .requestSentHUD(outcome: $outcome)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Gradient(colors: [.purple, .pink]))
    }
}

#if canImport(UIKit)
#Preview {
    RequestSentHUDPreview()
}
#endif
