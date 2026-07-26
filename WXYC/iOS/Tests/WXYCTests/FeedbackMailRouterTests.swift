//
//  FeedbackMailRouterTests.swift
//  WXYC
//
//  Pins the Station tab's "Send feedback" delivery decision. When the device
//  can compose mail in-app we present MFMailComposeViewController; when it
//  can't, presenting that controller aborts inside SwiftUI's sheet hosting on
//  iOS 26 (a null dynamic-cast in UICorePlatformViewHost.init), so the router
//  must fall back to a mailto: URL instead of the in-app composer.
//
//  Created by Jake Bromberg on 07/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYC
import Foundation

@Suite("FeedbackMailRouter")
struct FeedbackMailRouterTests {
    private let subject = "Feedback on the WXYC app"

    @Test("Presents the in-app composer when the device can send mail")
    func routesToComposerWhenAvailable() {
        let route = FeedbackMailRouter.route(canSendMail: true, subject: subject)

        #expect(route == .inAppComposer)
    }

    @Test("Falls back to a mailto: route when the device can't send mail")
    func fallsBackToMailtoWhenUnavailable() throws {
        let route = FeedbackMailRouter.route(canSendMail: false, subject: subject)

        guard case let .externalMailto(url) = route else {
            Issue.record("Expected an externalMailto route, got \(route)")
            return
        }

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == "feedback@wxyc.org")
        #expect(components.queryItems?.first { $0.name == "subject" }?.value == subject)
    }

    @Test("The mailto URL is percent-encoded so a subject with spaces survives")
    func mailtoURLIsPercentEncoded() {
        let url = FeedbackMailRouter.mailtoURL(subject: subject)

        #expect(url.absoluteString == "mailto:feedback@wxyc.org?subject=Feedback%20on%20the%20WXYC%20app")
    }

    @Test("The no-mail-handler fallback message names the feedback address so it stays recoverable")
    func noMailHandlerMessageNamesAddress() {
        #expect(FeedbackMailRouter.noMailHandlerMessage.contains(FeedbackMailRouter.recipient))
    }
}
