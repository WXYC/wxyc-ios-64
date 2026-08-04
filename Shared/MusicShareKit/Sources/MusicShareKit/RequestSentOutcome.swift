//
//  RequestSentOutcome.swift
//  MusicShareKit
//
//  The transient confirmation a listener earns for submitting a song request:
//  what the HUD shows, what VoiceOver says, and how long it stays up.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The result of submitting a song request, in the form the listener sees it.
///
/// Sending is fire-and-forget from the listener's side — nothing else in the
/// app changes when a request lands — so the confirmation is the only evidence
/// it worked. Both cases are modelled here so the failure gets the same care as
/// the success.
public enum RequestSentOutcome: Equatable, Sendable, CaseIterable {
    /// The booth received the request.
    case sent

    /// The request never reached the booth. Retryable.
    case failed

    /// Terse enough for the square HUD. VoiceOver gets
    /// ``accessibilityAnnouncement`` instead.
    var title: String {
        switch self {
        case .sent: "Request Sent"
        case .failed: "Not Sent"
        }
    }

    var systemImage: String {
        switch self {
        case .sent: "phone.connection.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    /// The full sentence, unconstrained by the HUD's square. A failure names
    /// the recovery, since a VoiceOver listener can't glance at the sheet
    /// behind the HUD to work out what to do next.
    var accessibilityAnnouncement: String {
        switch self {
        case .sent: "Request sent to the booth"
        case .failed: "Request not sent. Try again."
        }
    }

    /// How long the HUD stays up before dismissing itself. A failure asks the
    /// listener to act, so it outlasts a success they can catch in passing.
    var autoDismissDelay: Duration {
        switch self {
        case .sent: .seconds(1.5)
        case .failed: .seconds(2.5)
        }
    }
}
