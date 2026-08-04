//
//  RequestSentOutcomeTests.swift
//  MusicShareKit
//
//  Tests for the transient confirmation model shown after a song request.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import MusicShareKit

@Suite("RequestSentOutcome Tests")
struct RequestSentOutcomeTests {

    @Test("Sent reads as a confirmation")
    func sentCopy() {
        #expect(RequestSentOutcome.sent.title == "Request Sent")
        #expect(RequestSentOutcome.sent.systemImage == "phone.connection.fill")
    }

    @Test("Failed reads as a failure, not a confirmation")
    func failedCopy() {
        #expect(RequestSentOutcome.failed.title == "Not Sent")
        #expect(RequestSentOutcome.failed.systemImage == "exclamationmark.triangle.fill")
    }

    // The visual title is deliberately terse to fit the square HUD; VoiceOver
    // has no such constraint and gets the full sentence, including what to do
    // about a failure.
    @Test("VoiceOver hears more than the HUD shows")
    func announcementsAreFullSentences() {
        #expect(RequestSentOutcome.sent.accessibilityAnnouncement == "Request sent to the booth")
        #expect(RequestSentOutcome.failed.accessibilityAnnouncement == "Request not sent. Try again.")

        for outcome in RequestSentOutcome.allCases {
            #expect(outcome.accessibilityAnnouncement != outcome.title)
        }
    }

    // A failure asks the listener to do something about it, so it has to
    // outlast a success the eye can catch in passing.
    @Test("A failure lingers longer than a success")
    func failureLingersLonger() {
        #expect(RequestSentOutcome.failed.autoDismissDelay > RequestSentOutcome.sent.autoDismissDelay)
    }

    @Test("Every outcome stays on screen long enough to read")
    func everyOutcomeIsReadable() {
        for outcome in RequestSentOutcome.allCases {
            #expect(outcome.autoDismissDelay >= .seconds(1.5))
        }
    }
}
